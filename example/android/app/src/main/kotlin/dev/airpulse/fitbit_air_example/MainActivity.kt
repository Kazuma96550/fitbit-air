package dev.airpulse.fitbit_air_example

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Build
import android.Manifest
import android.content.pm.PackageManager
import android.provider.Settings

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fitbit_air_example/calendar")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "status" -> result.success(CalendarRelayService.status(this))
                        "apps" -> Thread {
                            try {
                                val apps = RelayAppSelection.available(this)
                                runOnUiThread { result.success(apps) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("APP_LIST", "Could not load apps.", null) }
                            }
                        }.start()
                        "clearHistory" -> {
                            RelayHistory.clear(this)
                            result.success(null)
                        }
                        "testPulse" -> {
                            checkNotNull(CalendarRelayService.active) { "Start the relay first." }.testPulse()
                            result.success(null)
                        }
                        "bluetoothSettings" -> {
                            startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                            result.success(null)
                        }
                        "labSettings" -> result.success(mapOf("secureDurationSeconds" to
                            getSharedPreferences("demo_lab", MODE_PRIVATE).getInt("duration", 30)))
                        "setLabSettings" -> {
                            val seconds = requireNotNull(call.argument<Int>("secureDurationSeconds"))
                            require(seconds in setOf(30, 60, 90))
                            getSharedPreferences("demo_lab", MODE_PRIVATE).edit().putInt("duration", seconds).apply()
                            result.success(null)
                        }
                        "captureConversations", "restrictConversations", "selectConversation", "clearConversations" -> {
                            check(!CalendarRelayService.isRunning) { "Stop the relay before changing conversation rules." }
                            when (call.method) {
                                "captureConversations" -> RelayConversations.capture(this, requireNotNull(call.argument<Boolean>("enabled")))
                                "restrictConversations" -> RelayConversations.setRestricted(this, requireNotNull(call.argument<Boolean>("enabled")))
                                "selectConversation" -> RelayConversations.select(this,
                                    requireNotNull(call.argument<String>("id")), requireNotNull(call.argument<Boolean>("enabled")),
                                    call.argument<Boolean>("allowNameMatch") == true)
                                "clearConversations" -> RelayConversations.clear(this)
                            }
                            result.success(null)
                        }
                        "setPulseStyle" -> {
                            check(!CalendarRelayService.isRunning) { "Stop the relay before changing the pulse style." }
                            RelayAppSelection.savePulseStyle(this, requireNotNull(call.argument<String>("style")))
                            result.success(null)
                        }
                        "selectApps" -> {
                            check(!CalendarRelayService.isRunning) { "Stop the relay before changing apps." }
                            val packages = requireNotNull(call.argument<List<String>>("packages"))
                            RelayAppSelection.save(this, packages.toSet())
                            result.success(null)
                        }
                        "settings" -> {
                            startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                            result.success(null)
                        }
                        "start" -> {
                            if (!CalendarRelayService.hasAccess(this) || !CalendarNotificationListener.connected) {
                                result.error("NOTIFICATION_ACCESS", "Enable notification access and wait for connection first.", null)
                            } else {
                                require(RelayAppSelection.selected(this).isNotEmpty()) { "Select at least one app first." }
                                if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
                                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 902)
                                CalendarRelayService.start(this)
                                result.success(null)
                            }
                        }
                        "stop" -> {
                            CalendarRelayService.stop()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("CALENDAR_RELAY", error.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fitbit_air_example/background")
            .setMethodCallHandler { call, result ->
                if (call.method == "startTest") {
                    val intent = Intent(this, HeadlessHapticService::class.java)
                    intent.putExtra("operation", call.argument<String>("operation") ?: "vibrate")
                    try {
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent)
                        else startService(intent)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("BACKGROUND_START", error.message, null)
                    }
                } else if (call.method == "getLastResult") {
                    result.success(getSharedPreferences("headless_test", MODE_PRIVATE).getString("result", null))
                } else result.notImplemented()
            }
    }
}
