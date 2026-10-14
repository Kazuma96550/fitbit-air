package dev.airpulse.fitbit_air_example

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Build

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
