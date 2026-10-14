package dev.airpulse.fitbit_air

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.fitbit.goldengate.bindings.coap.CoapEndpoint
import com.fitbit.goldengate.bindings.coap.data.Method
import com.fitbit.goldengate.bindings.coap.data.OutgoingRequestBuilder
import com.fitbit.goldengate.bindings.dtls.DtlsProtocolStatus.TlsProtocolState.TLS_STATE_SESSION
import com.fitbit.goldengate.bindings.io.RxSource
import com.fitbit.goldengate.bindings.io.TxSink
import com.fitbit.goldengate.bindings.node.BluetoothAddressNodeKey
import com.fitbit.goldengate.bindings.stack.DtlsSocketNetifGattlink
import com.fitbit.goldengate.bindings.stack.Stack
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry.RequestPermissionsResultListener
import io.reactivex.Single
import io.reactivex.disposables.CompositeDisposable
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.TimeUnit

/** Flutter bridge for the experimentally verified Fitbit Air haptic path. */
class FitbitAirPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private lateinit var appContext: Context
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingAction: (() -> Unit)? = null
    private val permissionListener = RequestPermissionsResultListener { requestCode, _, grantResults ->
        if (requestCode != PERMISSION_REQUEST) return@RequestPermissionsResultListener false
        val result = pendingPermissionResult
        pendingPermissionResult = null
        val action = pendingAction
        pendingAction = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) action?.invoke()
        else result?.error("BLUETOOTH_PERMISSION", "Nearby devices permission is required.", null)
        true
    }
    private var pendingResult: MethodChannel.Result? = null
    private val handler = Handler(Looper.getMainLooper())
    private var gatt: BluetoothGatt? = null
    private var txCharacteristic: BluetoothGattCharacteristic? = null
    private var txSink: TxSink? = null
    private var rxSource: RxSource? = null
    private var stack: Stack? = null
    private var endpoint: CoapEndpoint? = null
    private val disposables = CompositeDisposable()
    private val txQueue = ArrayDeque<ByteArray>()
    private var writeInFlight = false
    private var sessionStarted = false
    private var timeout: Runnable? = null
    private var activeOperation: Operation? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAirPaired" -> withBluetoothPermission(result) {
                result.success(findBondedAir() != null)
            }
            "vibrate" -> withBluetoothPermission(result) {
                startOperation(result, Operation.PreviewHaptic)
            }
            "getHapticIntensity" -> withBluetoothPermission(result) {
                startOperation(result, Operation.ReadHapticIntensity)
            }
            "setHapticIntensity" -> {
                val intensity = call.argument<Int>("intensity")
                if (intensity !in setOf(2, 3)) {
                    result.error("INVALID_INTENSITY", "Haptic intensity must be 2 (low) or 3 (high).", null)
                } else {
                    withBluetoothPermission(result) {
                        startOperation(result, Operation.SetHapticIntensity(intensity!!))
                    }
                }
            }
            "pulse" -> withBluetoothPermission(result) {
                startOperation(result, Operation.SinglePulse)
            }
            else -> result.notImplemented()
        }
    }

    private fun withBluetoothPermission(result: MethodChannel.Result, action: () -> Unit) {
        if (Build.VERSION.SDK_INT < 31 ||
            appContext.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        ) {
            action()
            return
        }
        val host = activity
        if (host == null) {
            result.error("NO_ACTIVITY", "Attach the Flutter view before calling Fitbit Air.", null)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("BUSY", "A Bluetooth permission request is already pending.", null)
            return
        }
        pendingPermissionResult = result
        pendingAction = action
        host.requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), PERMISSION_REQUEST)
    }

    @SuppressLint("MissingPermission")
    private fun findBondedAir(): BluetoothDevice? {
        val manager = appContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        return manager.adapter?.bondedDevices?.firstOrNull {
            it.name?.contains("Fitbit Air", ignoreCase = true) == true
        }
    }

    @SuppressLint("MissingPermission")
    private fun startOperation(result: MethodChannel.Result, operation: Operation) {
        if (pendingResult != null) {
            result.error("BUSY", "A Fitbit Air operation is already running.", null)
            return
        }
        val device = findBondedAir()
        if (device == null) {
            result.error("AIR_NOT_FOUND", "No bonded Fitbit Air found. Pair it in Google Health first.", null)
            return
        }
        pendingResult = result
        activeOperation = operation
        sessionStarted = false
        val deadline = Runnable { finishError("TIMEOUT", "Timed out connecting to Fitbit Air.") }
        timeout = deadline
        handler.postDelayed(deadline, OPERATION_TIMEOUT_MS)
        val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    finishError("GATT_CONNECT", "Bluetooth connection failed (status $status).")
                } else if (newState == android.bluetooth.BluetoothProfile.STATE_CONNECTED) {
                    g.discoverServices()
                }
            }

            override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    finishError("GATT_DISCOVERY", "Could not discover Air services (status $status).")
                    return
                }
                val rx = g.getService(TRACKER_SERVICE)?.getCharacteristic(TRACKER_RX)
                val cccd = rx?.getDescriptor(CCCD)
                if (rx == null || cccd == null || !g.setCharacteristicNotification(rx, true)) {
                    finishError("TRACKER_CHANNEL", "Air tracker channel is unavailable.")
                    return
                }
                val accepted = if (Build.VERSION.SDK_INT >= 33) {
                    g.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) == BluetoothGatt.GATT_SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    @Suppress("DEPRECATION")
                    g.writeDescriptor(cccd)
                }
                if (!accepted) finishError("SUBSCRIBE", "Could not subscribe to the tracker channel.")
            }

            override fun onDescriptorWrite(g: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
                if (descriptor.uuid != CCCD) return
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    finishError("SUBSCRIBE", "Tracker channel subscription failed (status $status).")
                } else {
                    startGoldengate(g, device)
                }
            }

            override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
                if (c.uuid == TRACKER_RX) rxSource?.receiveData(value)?.subscribe({}, { finishError("RX", it.message ?: "Receive failed.") })
            }

            @Suppress("DEPRECATION")
            override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
                if (Build.VERSION.SDK_INT < 33 && c.uuid == TRACKER_RX) {
                    rxSource?.receiveData(c.value ?: byteArrayOf())?.subscribe({}, { finishError("RX", it.message ?: "Receive failed.") })
                }
            }

            override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
                writeInFlight = false
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    finishError("TX", "Tracker channel write failed (status $status).")
                } else {
                    writeNextPacket(g)
                }
            }
        }
        val connection = device.connectGatt(appContext, false, callback, BluetoothDevice.TRANSPORT_LE)
        if (connection == null) {
            finishError("GATT_CONNECT", "Android did not create a Bluetooth connection.")
        } else {
            gatt = connection
        }
    }

    private fun startGoldengate(activeGatt: BluetoothGatt, device: BluetoothDevice) {
        try {
            val service = activeGatt.getService(TRACKER_SERVICE)
            val tx = service?.getCharacteristic(TRACKER_TX)
            val rx = service?.getCharacteristic(TRACKER_RX)
            if (tx == null || rx == null) {
                finishError("TRACKER_CHANNEL", "Air tracker channel characteristics are missing.")
                return
            }
            txCharacteristic = tx
            GoogleHealthNativeLoader.initialize(appContext)
            val sink = TxSink()
            val source = RxSource()
            txSink = sink
            rxSource = source
            disposables.add(sink.dataObservable.subscribe({ data ->
                synchronized(txQueue) { txQueue.addLast(data) }
                handler.post { writeNextPacket(gatt) }
            }, { finishError("GOLDENGATE_TX", it.message ?: "Transport send failed.") }))
            val newStack = Stack(BluetoothAddressNodeKey(device.address), sink.thisPointer, source.thisPointer, DtlsSocketNetifGattlink(), false)
            stack = newStack
            val coap = CoapEndpoint()
            coap.attach(newStack)
            endpoint = coap
            disposables.add(newStack.dtlsEventObservable.subscribe({ state ->
                if (state.state == TLS_STATE_SESSION && !sessionStarted) {
                    sessionStarted = true
                    handler.post { runOperation(coap) }
                }
            }, { finishError("DTLS", it.message ?: "Secure transport failed.") }))
            newStack.start()
        } catch (error: Throwable) {
            finishError("GOLDENGATE", error.message ?: error.toString())
        }
    }

    private fun runOperation(coap: CoapEndpoint) {
        when (val operation = activeOperation) {
            Operation.PreviewHaptic -> runBoundedHaptic(coap)
            Operation.ReadHapticIntensity -> runReadHapticIntensity(coap)
            is Operation.SetHapticIntensity -> runSetHapticIntensity(coap, operation.intensity)
            Operation.SinglePulse -> runSinglePulse(coap)
            null -> finishError("INTERNAL", "No Fitbit Air operation was selected.")
        }
    }

    private fun intensityProbe() = OutgoingRequestBuilder("/settings", Method.PUT)
        .expectSuccess(false).forceNonBlockwise(true)
        .body(byteArrayOf(0x0a, 0x01, 0x01)).build()

    private fun readIntensity(coap: CoapEndpoint): Single<Int> =
        coap.responseFor(intensityProbe()).timeout(3, TimeUnit.SECONDS).flatMap { response ->
            response.body.asData().map { body ->
                if (response.responseCode.responseClass.toInt() != 2 ||
                    !(body.contentEquals(byteArrayOf(10, 4, 10, 2, 8, 2)) ||
                        body.contentEquals(byteArrayOf(10, 4, 10, 2, 8, 3)))
                ) throw IllegalStateException("Air returned an unsupported haptic setting.")
                body.last().toInt()
            }
        }

    private fun runReadHapticIntensity(coap: CoapEndpoint) {
        disposables.add(readIntensity(coap).subscribe({ intensity ->
            finishSuccess(mapOf("intensity" to intensity))
        }, { error ->
            finishError("HAPTIC_READ_FAILED", error.message ?: "Could not read haptic intensity.")
        }))
    }

    private fun runSetHapticIntensity(coap: CoapEndpoint, requested: Int) {
        disposables.add(readIntensity(coap).flatMap { previous ->
            if (previous == requested) {
                Single.just(previous to false)
            } else {
                writeIntensity(coap, requested)
                    .flatMap { readIntensity(coap) }
                    .map { verified ->
                        if (verified != requested) throw IllegalStateException("Haptic intensity verification failed.")
                        previous to true
                    }
            }
        }.timeout(8, TimeUnit.SECONDS).subscribe({ (previous, changed) ->
            finishSuccess(
                mapOf(
                    "previousIntensity" to previous,
                    "currentIntensity" to requested,
                    "changed" to changed,
                    "verified" to true,
                ),
            )
        }, { error ->
            finishError("HAPTIC_WRITE_FAILED", error.message ?: "Could not set haptic intensity.")
        }))
    }

    /** One physical pulse: toggle to the other intensity and intentionally leave it there. */
    private fun runSinglePulse(coap: CoapEndpoint) {
        disposables.add(readIntensity(coap).flatMap { previous ->
            val current = if (previous == 2) 3 else 2
            writeIntensity(coap, current)
                .flatMap { readIntensity(coap) }
                .map { verified ->
                    if (verified != current) throw IllegalStateException("Single-pulse verification failed.")
                    previous to current
                }
        }.timeout(8, TimeUnit.SECONDS).subscribe({ (previous, current) ->
            finishSuccess(
                mapOf(
                    "previousIntensity" to previous,
                    "currentIntensity" to current,
                    "changed" to true,
                    "verified" to true,
                ),
            )
        }, { error ->
            finishError("HAPTIC_PULSE_FAILED", error.message ?: "Could not send a haptic pulse.")
        }))
    }

    private fun runBoundedHaptic(coap: CoapEndpoint) {
        disposables.add(readIntensity(coap).flatMap { original ->
                val alternate = if (original == 2) 3 else 2
                writeIntensity(coap, alternate)
                    .flatMap { Single.timer(800, TimeUnit.MILLISECONDS).map { original } }
                    .flatMap { prior -> writeIntensity(coap, prior).retry(2).map { prior } }
                    .flatMap { prior -> readIntensity(coap).map { verified ->
                        if (verified != prior) throw IllegalStateException("Original haptic setting was not verified restored.")
                        prior
                    } }.onErrorResumeNext { hapticError: Throwable ->
                        // A timed-out write may still have reached the Air. Restore the
                        // previously-read value before reporting the operation failure.
                        writeIntensity(coap, original).retry(2).flatMap<Int> {
                            Single.error(IllegalStateException(
                                "Haptic failed; the prior setting was restored but not verified.",
                                hapticError,
                            ))
                        }.onErrorResumeNext { restoreError: Throwable ->
                            Single.error(IllegalStateException(
                                "Haptic and restoration failed. Check vibration intensity in Google Health.",
                                restoreError,
                            ))
                        }
                    }
        }.timeout(12, TimeUnit.SECONDS).subscribe({ original ->
            finishSuccess(mapOf("originalIntensity" to original, "restored" to true, "verified" to true))
        }, { error -> finishError("HAPTIC_FAILED", error.message ?: "Haptic command failed; check Google Health settings." ) }))
    }

    private fun writeIntensity(coap: CoapEndpoint, intensity: Int): Single<Boolean> {
        val request = OutgoingRequestBuilder("/settings", Method.POST)
            .expectSuccess(false).forceNonBlockwise(true).maxResendCount(0)
            .body(byteArrayOf(10, 4, 10, 2, 8, intensity.toByte())).build()
        return coap.responseFor(request).timeout(3, TimeUnit.SECONDS).map { response ->
            if (response.responseCode.responseClass.toInt() != 2) throw IllegalStateException("Air rejected haptic setting change.")
            true
        }
    }

    @SuppressLint("MissingPermission")
    private fun writeNextPacket(activeGatt: BluetoothGatt?) {
        if (activeGatt == null || writeInFlight) return
        val characteristic = txCharacteristic ?: return
        val packet = synchronized(txQueue) { if (txQueue.isEmpty()) null else txQueue.removeFirst() } ?: return
        writeInFlight = true
        val accepted = if (Build.VERSION.SDK_INT >= 33) {
            activeGatt.writeCharacteristic(characteristic, packet, BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE) == BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION") characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            @Suppress("DEPRECATION") characteristic.value = packet
            @Suppress("DEPRECATION") activeGatt.writeCharacteristic(characteristic)
        }
        if (!accepted) {
            writeInFlight = false
            synchronized(txQueue) { txQueue.addFirst(packet) }
        }
    }

    @SuppressLint("MissingPermission")
    private fun finishSuccess(value: Map<String, Any>) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            handler.post { finishSuccess(value) }
            return
        }
        val reply = pendingResult ?: return
        pendingResult = null
        activeOperation = null
        closeTransport()
        reply.success(value)
    }

    @SuppressLint("MissingPermission")
    private fun finishError(code: String, message: String) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            handler.post { finishError(code, message) }
            return
        }
        val reply = pendingResult ?: return
        pendingResult = null
        activeOperation = null
        closeTransport()
        reply.error(code, message, null)
    }

    @SuppressLint("MissingPermission")
    private fun closeTransport() {
        timeout?.let(handler::removeCallbacks)
        timeout = null
        disposables.clear()
        endpoint?.close(); endpoint = null
        stack?.close(); stack = null
        rxSource?.close(); rxSource = null
        txSink?.close(); txSink = null
        txCharacteristic = null
        synchronized(txQueue) { txQueue.clear() }
        writeInFlight = false
        gatt?.disconnect(); gatt?.close(); gatt = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        closeTransport()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(permissionListener)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detachActivity()

    private fun detachActivity() {
        activityBinding?.removeRequestPermissionsResultListener(permissionListener)
        activityBinding = null
        activity = null
    }

    companion object {
        private const val CHANNEL = "fitbit_air"
        private const val PERMISSION_REQUEST = 49217
        private const val OPERATION_TIMEOUT_MS = 45_000L
        private val TRACKER_SERVICE = UUID.fromString("abbaff00-e56a-484c-b832-8b17cf6cbfe8")
        private val TRACKER_TX = UUID.fromString("abbaff01-e56a-484c-b832-8b17cf6cbfe8")
        private val TRACKER_RX = UUID.fromString("abbaff02-e56a-484c-b832-8b17cf6cbfe8")
        private val CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    private sealed interface Operation {
        data object PreviewHaptic : Operation
        data object ReadHapticIntensity : Operation
        data class SetHapticIntensity(val intensity: Int) : Operation
        data object SinglePulse : Operation
    }
}
