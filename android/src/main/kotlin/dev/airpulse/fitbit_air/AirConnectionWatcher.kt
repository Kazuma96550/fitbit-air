package dev.airpulse.fitbit_air

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build

/**
 * Reports whether the Air's Bluetooth link is up, from Android's system
 * connection broadcasts. Opens no connection of its own; Google Health keeps
 * the link while the Air is in range, so a disconnect usually means out of
 * range, Bluetooth off, or the Air shut down.
 */
@SuppressLint("MissingPermission")
internal class AirConnectionWatcher(
    private val context: Context,
    private val device: BluetoothDevice,
    private val emit: (Map<String, Any>) -> Unit,
) {
    private var registered = false
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val changed = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
            } else {
                @Suppress("DEPRECATION") intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
            }
            if (changed?.address != device.address) return
            when (intent.action) {
                BluetoothDevice.ACTION_ACL_CONNECTED -> publish(true)
                BluetoothDevice.ACTION_ACL_DISCONNECTED -> publish(false)
            }
        }
    }

    fun start() {
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
        registered = true
        publish(isConnected(context, device))
    }

    fun close() {
        if (!registered) return
        registered = false
        runCatching { context.unregisterReceiver(receiver) }
    }

    private fun publish(connected: Boolean) {
        emit(mapOf("connected" to connected, "receivedAtMillis" to System.currentTimeMillis()))
    }

    companion object {
        fun isConnected(context: Context, device: BluetoothDevice): Boolean {
            val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            return manager.getConnectionState(device, BluetoothProfile.GATT) == BluetoothProfile.STATE_CONNECTED
        }
    }
}
