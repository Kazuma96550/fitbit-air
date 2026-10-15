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
import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
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
import io.flutter.plugin.common.EventChannel
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
    private lateinit var heartRateChannel: EventChannel
    private lateinit var deviceEventChannel: EventChannel
    private lateinit var secureEventChannel: EventChannel
    private var secureEvents: EventChannel.EventSink? = null
    private var secureCapture: AirSecureEventCapture? = null
    private var diagnosticEvents: EventChannel.EventSink? = null
    private var eventMonitor: AirEventMonitor? = null
    private var heartRateEvents: EventChannel.EventSink? = null
    private var heartRateStreamGeneration = 0
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
        if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) action?.invoke()
        else result?.error("BLUETOOTH_PERMISSION", "Nearby devices permission is required.", null)
        true
    }
    private var pendingResult: MethodChannel.Result? = null
    private val transportOwner = Any()
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
    private val infoReads = ArrayDeque<BluetoothGattCharacteristic>()
    private val deviceInfo = mutableMapOf<String, Any>()
    private var heartRateSubscribed = false
    private var scanCallback: ScanCallback? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        heartRateChannel = EventChannel(binding.binaryMessenger, "fitbit_air/heart_rate")
        heartRateChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                val address = (arguments as? Map<*, *>)?.get("deviceId") as? String
                if (address != null && !BluetoothAdapter.checkBluetoothAddress(address)) {
                    events.error("INVALID_DEVICE", "Select a discovered heart-rate sensor first.", null)
                    events.endOfStream()
                    return
                }
                if (pendingResult != null || pendingPermissionResult != null || diagnosticEvents != null) {
                    events.error("BUSY", "Another Bluetooth operation is running.", null)
                    events.endOfStream()
                    return
                }
                heartRateEvents = events
                val generation = ++heartRateStreamGeneration
                val streamResult = object : MethodChannel.Result {
                    override fun success(result: Any?) { }
                    override fun error(code: String, message: String?, details: Any?) {
                        if (heartRateEvents === events) heartRateEvents = null
                        events.error(code, message, details)
                        events.endOfStream()
                    }
                    override fun notImplemented() = error("INTERNAL", "Heart-rate stream unavailable.", null)
                }
                withBluetoothPermission(streamResult) {
                    if (generation == heartRateStreamGeneration && heartRateEvents === events) {
                        startOperation(streamResult, Operation.ReadHeartRate, address)
                    }
                }
            }

            override fun onCancel(arguments: Any?) {
                heartRateStreamGeneration++
                heartRateEvents = null
                if (activeOperation == Operation.ReadHeartRate) {
                    // Do not emit an error into a stream the consumer cancelled.
                    pendingResult = null
                    activeOperation = null
                    closeTransport()
                }
            }
        })
        secureEventChannel = EventChannel(binding.binaryMessenger, "fitbit_air/secure_events")
        secureEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                if (pendingResult != null || pendingPermissionResult != null || diagnosticEvents != null || secureEvents != null) {
                    events.error("BUSY", "Another Bluetooth operation is running.", null)
                    events.endOfStream()
                    return
                }
                secureEvents = events
                val reply = object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (secureEvents === events) {
                            events.success((result as Map<*, *>) + mapOf("kind" to "complete", "receivedAtMillis" to System.currentTimeMillis()))
                            secureEvents = null
                            events.endOfStream()
                        }
                    }
                    override fun error(code: String, message: String?, details: Any?) {
                        if (secureEvents === events) {
                            secureEvents = null
                            events.error(code, message, details)
                            events.endOfStream()
                        }
                    }
                    override fun notImplemented() = error("INTERNAL", "Secure event capture unavailable.", null)
                }
                withBluetoothPermission(reply) {
                    if (secureEvents === events) startOperation(reply, Operation.CaptureSecureEvents)
                }
            }
            override fun onCancel(arguments: Any?) {
                secureEvents = null
                if (activeOperation == Operation.CaptureSecureEvents) {
                    pendingResult = null
                    activeOperation = null
                    closeTransport()
                }
            }
        })
        deviceEventChannel = EventChannel(binding.binaryMessenger, "fitbit_air/device_events")
        deviceEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                if (pendingResult != null || pendingPermissionResult != null || diagnosticEvents != null) {
                    events.error("BUSY", "Another Bluetooth operation is running.", null)
                    events.endOfStream()
                    return
                }
                diagnosticEvents = events
                val permissionResult = object : MethodChannel.Result {
                    override fun success(result: Any?) { }
                    override fun error(code: String, message: String?, details: Any?) {
                        if (diagnosticEvents === events) {
                            eventMonitor?.close()
                            eventMonitor = null
                            diagnosticEvents = null
                            AirTransportLease.release(transportOwner)
                        }
                        events.error(code, message, details)
                        events.endOfStream()
                    }
                    override fun notImplemented() = error("INTERNAL", "Diagnostic events unavailable.", null)
                }
                withBluetoothPermission(permissionResult) {
                    if (diagnosticEvents !== events) return@withBluetoothPermission
                    val device = findBondedAir()
                    if (device == null) {
                        permissionResult.error("AIR_NOT_FOUND", "Pair your Air in Google Health first.", null)
                    } else {
                        if (!AirTransportLease.tryAcquire(transportOwner)) {
                            permissionResult.error("BUSY", "Another Flutter engine owns the Bluetooth transport.", null)
                            return@withBluetoothPermission
                        }
                        val monitor = AirEventMonitor(appContext, { event ->
                            if (diagnosticEvents === events) events.success(event)
                        }, { code, message -> permissionResult.error(code, message, null) })
                        eventMonitor = monitor
                        try {
                            monitor.start(device)
                        } catch (error: Exception) {
                            permissionResult.error("EVENT_CONNECT", error.message ?: "Could not start diagnostic connection.", null)
                        }
                    }
                }
            }

            override fun onCancel(arguments: Any?) {
                val wasActive = diagnosticEvents != null
                diagnosticEvents = null
                eventMonitor?.close()
                eventMonitor = null
                if (wasActive) AirTransportLease.release(transportOwner)
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "cancelOperation" -> {
                if (diagnosticEvents != null) {
                    eventMonitor?.close()
                    eventMonitor = null
                    diagnosticEvents?.endOfStream()
                    diagnosticEvents = null
                    AirTransportLease.release(transportOwner)
                }
                if (activeOperation == Operation.PreviewHaptic ||
                    activeOperation == Operation.SinglePulse || activeOperation is Operation.SetHapticIntensity) {
                    result.error("CANNOT_CANCEL_WRITE", "Wait for the haptic write and verification to finish.", null)
                    return
                }
                finishError("CANCELLED", "Fitbit Air operation cancelled.")
                result.success(null)
            }
            "scanHeartRateDevices" -> withBluetoothPermission(result, needsScan = true) { scanHeartRateDevices(result) }
            "readHeartRate" -> withBluetoothPermission(result) {
                val address = call.argument<String>("deviceId")
                if (address != null && !BluetoothAdapter.checkBluetoothAddress(address)) {
                    result.error("INVALID_DEVICE", "Select a discovered heart-rate sensor first.", null)
                } else startOperation(result, Operation.ReadHeartRate, address)
            }
            "readDeviceInfo" -> withBluetoothPermission(result) {
                startOperation(result, Operation.ReadDeviceInfo)
            }
            "isAirPaired" -> withBluetoothPermission(result) {
                result.success(findBondedAir() != null)
            }
            "vibrate" -> withBluetoothPermission(result) {
                startOperation(result, Operation.PreviewHaptic)
            }
            "getHapticIntensity" -> withBluetoothPermission(result) {
                startOperation(result, Operation.ReadHapticIntensity)
            }
            "probeBatteryAccess" -> withBluetoothPermission(result) {
                startOperation(result, Operation.ProbeBatteryAccess)
            }
            "probeReadOnlyResources" -> withBluetoothPermission(result) {
                startOperation(result, Operation.ProbeReadOnlyResources)
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

    private fun withBluetoothPermission(result: MethodChannel.Result, needsScan: Boolean = false, action: () -> Unit) {
        val permissions = if (Build.VERSION.SDK_INT >= 31) {
            if (needsScan) arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN)
            else arrayOf(Manifest.permission.BLUETOOTH_CONNECT)
        } else if (needsScan) arrayOf(Manifest.permission.ACCESS_FINE_LOCATION) else emptyArray()
        if (permissions.all { appContext.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) {
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
        host.requestPermissions(permissions, PERMISSION_REQUEST)
    }

    @SuppressLint("MissingPermission")
    private fun scanHeartRateDevices(result: MethodChannel.Result) {
        if (pendingResult != null || diagnosticEvents != null) {
            result.error("BUSY", "A Fitbit Air operation is already running.", null)
            return
        }
        val manager = appContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val scanner = manager.adapter?.bluetoothLeScanner
        if (scanner == null) {
            result.error("BLUETOOTH_OFF", "Enable Bluetooth before scanning.", null)
            return
        }
        if (!AirTransportLease.tryAcquire(transportOwner)) {
            result.error("BUSY", "Another Flutter engine owns the Bluetooth transport.", null)
            return
        }
        pendingResult = result
        val found = mutableMapOf<String, Map<String, Any>>()
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, scan: ScanResult) {
                handler.post {
                    if (scanCallback !== this) return@post
                    found[scan.device.address] = mapOf(
                        "deviceId" to scan.device.address,
                        "name" to (scan.scanRecord?.deviceName ?: scan.device.name ?: "Heart-rate sensor"),
                        "rssi" to scan.rssi,
                    )
                }
            }
            override fun onScanFailed(errorCode: Int) {
                finishError("SCAN_FAILED", "Bluetooth scan failed (status $errorCode).")
            }
        }
        scanCallback = callback
        val deadline = Runnable { finishSuccess(mapOf("devices" to found.values.toList())) }
        timeout = deadline
        handler.postDelayed(deadline, 8_000)
        try {
            scanner.startScan(
                listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(HEART_RATE_SERVICE)).build()),
                ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),
                callback,
            )
        } catch (error: Exception) {
            finishError("SCAN_FAILED", error.message ?: "Could not start Bluetooth scan.")
        }
    }

    @SuppressLint("MissingPermission")
    private fun findBondedAir(): BluetoothDevice? {
        val manager = appContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        return manager.adapter?.bondedDevices?.firstOrNull {
            it.name?.contains("Fitbit Air", ignoreCase = true) == true
        }
    }

    @SuppressLint("MissingPermission")
    private fun startOperation(result: MethodChannel.Result, operation: Operation, deviceId: String? = null) {
        if (pendingResult != null || diagnosticEvents != null) {
            result.error("BUSY", "A Fitbit Air operation is already running.", null)
            return
        }
        val device = if (deviceId == null) findBondedAir() else {
            val manager = appContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            manager.adapter?.getRemoteDevice(deviceId)
        }
        if (device == null) {
            result.error("AIR_NOT_FOUND", "No bonded Fitbit Air found. Pair it in Google Health first.", null)
            return
        }
        if (!AirTransportLease.tryAcquire(transportOwner)) {
            result.error("BUSY", "Another Flutter engine owns the Bluetooth transport.", null)
            return
        }
        pendingResult = result
        heartRateSubscribed = false
        activeOperation = operation
        sessionStarted = false
        val deadline = Runnable {
            if (activeOperation == Operation.ReadHeartRate) {
                finishError("HEART_RATE_TIMEOUT", if (heartRateSubscribed)
                    "Air accepted the heart-rate subscription but sent no measurements. Heart-rate sharing may be disabled or paused."
                else "Heart-rate subscription was not acknowledged before the deadline.")
            } else finishError("TIMEOUT", "Fitbit Air operation timed out.")
        }
        timeout = deadline
        handler.postDelayed(deadline, OPERATION_TIMEOUT_MS)
        val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
                if (g !== gatt) return
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    finishError("GATT_CONNECT", "Bluetooth connection failed (status $status).")
                } else if (newState == android.bluetooth.BluetoothProfile.STATE_CONNECTED) {
                    g.discoverServices()
                } else if (newState == android.bluetooth.BluetoothProfile.STATE_DISCONNECTED) {
                    finishError("GATT_DISCONNECTED", "Air disconnected before the operation finished.")
                }
            }

            override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
                if (g !== gatt) return
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    finishError("GATT_DISCOVERY", "Could not discover Air services (status $status).")
                    return
                }
                if (activeOperation == Operation.ReadDeviceInfo) {
                    readDeviceInformation(g, device)
                    return
                }
                if (activeOperation == Operation.ReadHeartRate) {
                    subscribeHeartRate(g)
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
                if (g !== gatt) return
                android.util.Log.d("FitbitAir", "CCCD ${descriptor.characteristic.uuid} status=$status")
                if (descriptor.uuid != CCCD) return
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    finishError("SUBSCRIBE", "Tracker channel subscription failed (status $status).")
                } else if (activeOperation == Operation.ReadHeartRate) {
                    heartRateSubscribed = true
                    // The next standard Heart Rate Measurement completes this read.
                } else {
                    startGoldengate(g, device)
                }
            }

            override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
                if (g !== gatt) return
                if (c.uuid == HEART_RATE_MEASUREMENT && activeOperation == Operation.ReadHeartRate) {
                    android.util.Log.d("FitbitAir", "Heart-rate notification length=${value.size}")
                    handleHeartRate(value)
                    return
                }
                if (c.uuid == TRACKER_RX) rxSource?.receiveData(value)?.subscribe({}, { finishError("RX", it.message ?: "Receive failed.") })
            }

            @Suppress("DEPRECATION")
            override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
                if (g !== gatt) return
                if (Build.VERSION.SDK_INT < 33 && c.uuid == HEART_RATE_MEASUREMENT && activeOperation == Operation.ReadHeartRate) {
                    handleHeartRate(c.value ?: byteArrayOf())
                    return
                }
                if (Build.VERSION.SDK_INT < 33 && c.uuid == TRACKER_RX) {
                    rxSource?.receiveData(c.value ?: byteArrayOf())?.subscribe({}, { finishError("RX", it.message ?: "Receive failed.") })
                }
            }

            override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
                if (g !== gatt) return
                writeInFlight = false
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    finishError("TX", "Tracker channel write failed (status $status).")
                } else {
                    writeNextPacket(g)
                }
            }

            override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
                if (g !== gatt) return
                if (activeOperation == Operation.ReadDeviceInfo) handleInfoRead(g, c, value, status)
            }

            @Suppress("DEPRECATION")
            override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
                if (g !== gatt) return
                if (Build.VERSION.SDK_INT < 33 && activeOperation == Operation.ReadDeviceInfo) {
                    handleInfoRead(g, c, c.value ?: byteArrayOf(), status)
                }
            }
        }
        val connection = try {
            device.connectGatt(appContext, false, callback, BluetoothDevice.TRANSPORT_LE)
        } catch (error: Exception) {
            finishError("GATT_CONNECT", error.message ?: "Could not start Bluetooth connection.")
            return
        }
        if (connection == null) {
            finishError("GATT_CONNECT", "Android did not create a Bluetooth connection.")
        } else {
            gatt = connection
        }
    }

    @SuppressLint("MissingPermission")
    private fun subscribeHeartRate(g: BluetoothGatt) {
        val characteristic = g.getService(HEART_RATE_SERVICE)?.getCharacteristic(HEART_RATE_MEASUREMENT)
        val descriptor = characteristic?.getDescriptor(CCCD)
        if (characteristic == null || descriptor == null || !g.setCharacteristicNotification(characteristic, true)) {
            finishError("HEART_RATE_UNAVAILABLE", "Air does not expose standard heart-rate notifications.")
            return
        }
        val accepted = if (Build.VERSION.SDK_INT >= 33) {
            g.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) == BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            @Suppress("DEPRECATION")
            g.writeDescriptor(descriptor)
        }
        if (!accepted) finishError("SUBSCRIBE", "Could not subscribe to heart rate.")
    }

    private fun handleHeartRate(bytes: ByteArray) {
        try {
            var offset = 0
            fun u8(): Int {
                require(offset < bytes.size) { "Truncated heart-rate measurement." }
                return bytes[offset++].toInt() and 0xff
            }
            fun u16(): Int = u8() or (u8() shl 8)
            val flags = u8()
            val bpm = if (flags and 1 == 0) u8() else u16()
            val contactSupported = flags and 4 != 0
            val values = mutableMapOf<String, Any>(
                "beatsPerMinute" to bpm,
                "receivedAtMillis" to System.currentTimeMillis(),
                "contactSupported" to contactSupported,
            )
            if (contactSupported) values["contactDetected"] = flags and 2 != 0
            if (flags and 8 != 0) values["energyExpendedKj"] = u16()
            val rr = mutableListOf<Double>()
            if (flags and 16 != 0) {
                require(offset < bytes.size) { "Missing RR intervals." }
                while (offset < bytes.size) rr.add(u16() * 1000.0 / 1024.0)
            }
            values["rrIntervalsMillis"] = rr
            handler.post {
                val events = heartRateEvents
                if (events != null && activeOperation == Operation.ReadHeartRate) {
                    timeout?.let(handler::removeCallbacks)
                    timeout = null
                    events.success(values)
                } else if (activeOperation == Operation.ReadHeartRate) finishSuccess(values)
            }
        } catch (error: IllegalArgumentException) {
            finishError("HEART_RATE_FORMAT", error.message ?: "Malformed heart-rate measurement.")
        }
    }

    @SuppressLint("MissingPermission")
    private fun readDeviceInformation(g: BluetoothGatt, device: BluetoothDevice) {
        deviceInfo.clear()
        infoReads.clear()
        deviceInfo["name"] = device.name ?: "Fitbit Air"
        deviceInfo["services"] = g.services.map { service ->
            mapOf(
                "uuid" to service.uuid.toString(),
                "characteristics" to service.characteristics.map { characteristic ->
                    mapOf("uuid" to characteristic.uuid.toString(), "properties" to characteristic.properties)
                },
            )
        }
        for (service in g.services) {
            for (characteristic in service.characteristics) {
                if (INFO_CHARACTERISTICS.containsKey(characteristic.uuid) &&
                    characteristic.properties and BluetoothGattCharacteristic.PROPERTY_READ != 0
                ) infoReads.addLast(characteristic)
            }
        }
        nextInfoRead(g)
    }

    @SuppressLint("MissingPermission")
    private fun nextInfoRead(g: BluetoothGatt) {
        val characteristic = infoReads.pollFirst()
        if (characteristic == null) {
            finishSuccess(deviceInfo.toMap())
        } else if (!g.readCharacteristic(characteristic)) {
            deviceInfo["${INFO_CHARACTERISTICS[characteristic.uuid]}Error"] = "Android rejected read"
            nextInfoRead(g)
        }
    }

    private fun handleInfoRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, bytes: ByteArray, status: Int) {
        val key = INFO_CHARACTERISTICS[c.uuid] ?: return
        if (status == BluetoothGatt.GATT_SUCCESS) {
            if (key == "connectionStatus" || key == "connectionConfiguration") {
                try {
                    val buffer = java.nio.ByteBuffer.wrap(bytes).order(java.nio.ByteOrder.LITTLE_ENDIAN)
                    if (key == "connectionStatus") {
                        require(bytes.size >= 7) { "Truncated connection status" }
                        val flags = buffer.get().toInt() and 0xff
                        deviceInfo[key] = mapOf(
                            "bonded" to (flags and 1 != 0),
                            "encrypted" to (flags and 2 != 0),
                            "dataLengthExtension" to (flags and 4 != 0),
                            "dataLengthReboot" to (flags and 8 != 0),
                            "maxTxPayload" to (buffer.get().toInt() and 0xff),
                            "maxTxTimeMicros" to (buffer.short.toInt() and 0xffff),
                            "maxRxPayload" to (buffer.get().toInt() and 0xff),
                            "maxRxTimeMicros" to (buffer.short.toInt() and 0xffff),
                        )
                    } else {
                        require(bytes.size >= 9) { "Truncated connection configuration" }
                        deviceInfo[key] = mapOf(
                            "intervalMillis" to (buffer.short.toInt() and 0xffff) * 1.25,
                            "peripheralLatency" to (buffer.short.toInt() and 0xffff),
                            "supervisionTimeoutMillis" to (buffer.short.toInt() and 0xffff) * 10,
                            "mtu" to (buffer.short.toInt() and 0xffff),
                            "mode" to when (buffer.get().toInt()) {
                                0 -> "default"
                                1 -> "fast"
                                2 -> "slow"
                                else -> "unknown"
                            },
                        )
                    }
                } catch (error: IllegalArgumentException) {
                    deviceInfo["${key}Error"] = error.message ?: "Invalid link status"
                }
            } else if (key == "batteryPercent") {
                val battery = bytes.firstOrNull()?.toInt()?.and(0xff)
                if (battery != null && battery in 0..100) deviceInfo[key] = battery
            } else {
                deviceInfo[key] = bytes.toString(Charsets.UTF_8).trimEnd('\u0000')
            }
        } else {
            deviceInfo["${key}Error"] = "GATT status $status"
        }
        nextInfoRead(g)
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

    @SuppressLint("MissingPermission")
    private fun runOperation(coap: CoapEndpoint) {
        when (val operation = activeOperation) {
            Operation.ReadDeviceInfo -> finishError("INTERNAL", "Device information does not use DTLS.")
            Operation.ReadHeartRate -> finishError("INTERNAL", "Standard heart rate does not use DTLS.")
            Operation.PreviewHaptic -> runBoundedHaptic(coap)
            Operation.ReadHapticIntensity -> runReadHapticIntensity(coap)
            Operation.ProbeBatteryAccess -> runBatteryAccessProbe(coap)
            Operation.ProbeReadOnlyResources -> disposables.add(AirReadOnlyResources.probe(coap)
                .subscribe({ finishSuccess(it) }, {
                    finishError("RESOURCE_PROBE_FAILED", "Read-only resource probe failed.")
                }))
            Operation.CaptureSecureEvents -> {
                val events = secureEvents ?: run {
                    finishError("CANCELLED", "Secure event listener was cancelled.")
                    return
                }
                val peer = gatt?.device ?: run {
                    finishError("GATT_DISCONNECTED", "Secure event connection ended.")
                    return
                }
                try {
                    // Mirror the non-authenticated resource filter group, not GROUP_0.
                    coap.setFilterGroup(com.fitbit.goldengate.bindings.coap.CoapGroupRequestFilterMode.GROUP_1,
                        BluetoothAddressNodeKey(peer.address))
                    val capture = AirSecureEventCapture(coap) { event ->
                        handler.post { if (secureEvents === events) events.success(event) }
                    }
                    secureCapture = capture
                    disposables.add(capture.start().subscribe({ finishSuccess(it) }, {
                        finishError("EVENT_CAPTURE_FAILED", "Could not observe secure device events.")
                    }))
                } catch (_: LinkageError) {
                    finishError("EVENT_CAPTURE_ABI", "Installed native transport lacks compatible event-server bindings.")
                } catch (_: Exception) {
                    finishError("EVENT_CAPTURE_FAILED", "Could not initialize secure event capture.")
                }
            }
            is Operation.SetHapticIntensity -> runSetHapticIntensity(coap, operation.intensity)
            Operation.SinglePulse -> runSinglePulse(coap)
            null -> finishError("INTERNAL", "No Fitbit Air operation was selected.")
        }
    }

    /** Read-only research probe. Never exposes device identifiers or raw body. */
    private fun runBatteryAccessProbe(coap: CoapEndpoint) {
        val request = OutgoingRequestBuilder("/md/606", Method.GET)
            .expectSuccess(false).forceNonBlockwise(true).maxResendCount(0).build()
        disposables.add(coap.responseFor(request).timeout(5, TimeUnit.SECONDS)
            .flatMap { response -> response.body.asData().map { bytes ->
                mutableMapOf<String, Any>(
                    "responseClass" to response.responseCode.responseClass.toInt(),
                    "detail" to response.responseCode.detail.toInt(),
                    "bodyLength" to bytes.size,
                ).apply {
                    if (response.responseCode.responseClass.toInt() == 2) {
                        try { putAll(AirBatteryDecoder.decode(bytes)) }
                        catch (_: Exception) { put("decodeError", "Could not decode battery fields.") }
                    }
                }
            } }.subscribe({ result -> finishSuccess(result) }, { error ->
                finishError("BATTERY_PROBE_FAILED", error.message ?: "Battery access probe failed.")
            }))
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
                        writeIntensity(coap, original).retry(2).onErrorResumeNext { restoreError: Throwable ->
                            Single.error(IllegalStateException(
                                "Haptic and restoration failed. Check vibration intensity in Google Health.",
                                restoreError,
                            ))
                        }.flatMap<Int> {
                            Single.error(IllegalStateException(
                                "Haptic failed; the prior setting was restored but not verified.",
                                hapticError,
                            ))
                        }
                    }
        // Each request has its own deadline. An outer short timeout could
        // dispose the recovery write; the operation-wide 45s guard remains.
        }.subscribe({ original ->
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
        runCatching {
            scanCallback?.let { callback ->
                val manager = appContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                manager.adapter?.bluetoothLeScanner?.stopScan(callback)
            }
        }
        scanCallback = null
        infoReads.clear()
        deviceInfo.clear()
        timeout?.let(handler::removeCallbacks)
        timeout = null
        runCatching { disposables.clear() }
        runCatching { secureCapture?.close() }; secureCapture = null
        runCatching { endpoint?.close() }; endpoint = null
        runCatching { stack?.close() }; stack = null
        runCatching { rxSource?.close() }; rxSource = null
        runCatching { txSink?.close() }; txSink = null
        txCharacteristic = null
        synchronized(txQueue) { txQueue.clear() }
        writeInFlight = false
        runCatching { gatt?.disconnect() }
        runCatching { gatt?.close() }; gatt = null
        AirTransportLease.release(transportOwner)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        secureEventChannel.setStreamHandler(null)
        secureEvents = null
        heartRateChannel.setStreamHandler(null)
        heartRateEvents = null
        deviceEventChannel.setStreamHandler(null)
        diagnosticEvents = null
        eventMonitor?.close()
        eventMonitor = null
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
        private val HEART_RATE_SERVICE = UUID.fromString("0000180d-0000-1000-8000-00805f9b34fb")
        private val HEART_RATE_MEASUREMENT = UUID.fromString("00002a37-0000-1000-8000-00805f9b34fb")
        private val INFO_CHARACTERISTICS = mapOf(
            UUID.fromString("abbafd01-e56a-484c-b832-8b17cf6cbfe8") to "connectionConfiguration",
            UUID.fromString("abbafd02-e56a-484c-b832-8b17cf6cbfe8") to "connectionStatus",
            UUID.fromString("00002a19-0000-1000-8000-00805f9b34fb") to "batteryPercent",
            UUID.fromString("00002a24-0000-1000-8000-00805f9b34fb") to "model",
            UUID.fromString("00002a26-0000-1000-8000-00805f9b34fb") to "firmware",
            UUID.fromString("00002a27-0000-1000-8000-00805f9b34fb") to "hardware",
            UUID.fromString("00002a29-0000-1000-8000-00805f9b34fb") to "manufacturer",
        )
    }

    private sealed interface Operation {
        data object ReadHeartRate : Operation
        data object ReadDeviceInfo : Operation
        data object PreviewHaptic : Operation
        data object ReadHapticIntensity : Operation
        data object ProbeBatteryAccess : Operation
        data object ProbeReadOnlyResources : Operation
        data object CaptureSecureEvents : Operation
        data class SetHapticIntensity(val intensity: Int) : Operation
        data object SinglePulse : Operation
    }
}
