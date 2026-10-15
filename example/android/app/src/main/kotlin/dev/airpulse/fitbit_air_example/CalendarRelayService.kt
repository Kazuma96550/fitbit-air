package dev.airpulse.fitbit_air_example

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/** User-started example relay; never starts work from a notification callback. */
class CalendarRelayService : Service() {
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var filter: CalendarAlertFilter? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var pending = 0
    private var ready = false
    private var stopping = false
    private var sequence = 0
    private val handler = Handler(Looper.getMainLooper())
    private val watchdog = Runnable {
        saveOutcome("Relay command exceeded its deadline; stopped. Delivery is uncertain; no retry.")
        stopSelf()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        starting = false
        if (cancelStart) {
            cancelStart = false
            saveOutcome("Relay stopped.")
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == STOP) {
            requestStop("Relay stopped.")
            return START_NOT_STICKY
        }
        if (engine != null) return START_NOT_STICKY
        if (!hasAccess(this) || !CalendarNotificationListener.connected) {
            saveOutcome("Enable notification access and wait for the listener to connect, then start again.")
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Calendar to Air", NotificationManager.IMPORTANCE_LOW)
            )
            val stop = PendingIntent.getService(this, 0,
                Intent(this, CalendarRelayService::class.java).setAction(STOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val open = PendingIntent.getActivity(this, 1, Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
                else @Suppress("DEPRECATION") Notification.Builder(this)
            val notification = builder.setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
                .setContentTitle("Google Calendar → Fitbit Air")
                .setContentText("Calendar alerts trigger two pulses. Tap Stop to disable.")
                .setContentIntent(open).setOngoing(true)
                .addAction(Notification.Action.Builder(null, "Stop", stop).build()).build()
            if (Build.VERSION.SDK_INT >= 29)
                startForeground(902, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            else startForeground(902, notification)
            active = this
            saveOutcome("Starting calendar relay…")
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            val relayEngine = FlutterEngine(applicationContext)
            engine = relayEngine
            channel = MethodChannel(relayEngine.dartExecutor.binaryMessenger, "fitbit_air_example/calendar_worker")
                .also { worker ->
                    worker.setMethodCallHandler { call, result ->
                        if (call.method == "ready") {
                            try {
                                check(hasAccess(this) && CalendarNotificationListener.connected)
                                filter = CalendarAlertFilter(System.currentTimeMillis(),
                                    CalendarNotificationListener.existingCalendarKeys())
                                ready = true
                                handler.removeCallbacks(watchdog)
                                saveOutcome("Listening for new Google Calendar alerts.")
                                result.success(null)
                                if (stopping) requestStop("Relay stopped.")
                            } catch (error: Exception) {
                                result.error("NOTIFICATION_ACCESS", "Notification listener unavailable.", null)
                                requestStop("Notification listener unavailable. Enable access and start again.")
                            }
                        } else result.notImplemented()
                    }
                }
            handler.postDelayed(watchdog, 60_000)
            relayEngine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "airCalendarRelay"))
        } catch (error: Exception) {
            saveOutcome("Relay startup failed: ${error.javaClass.simpleName}")
            stopSelf()
        }
        return START_NOT_STICKY
    }

    fun onAlert(packageName: String, key: String, postedAt: Long, ongoing: Boolean, summary: Boolean) {
        if (!ready || stopping) return
        val now = System.currentTimeMillis()
        if (filter?.accept(packageName, key, postedAt, now, ongoing, summary) != true) return
        if (pending >= 4) {
            saveOutcome("Calendar alert dropped: queue full.")
            return
        }
        if (pending++ == 0) {
            handler.removeCallbacks(watchdog)
            handler.postDelayed(watchdog, 240_000)
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "fitbit_air_example:CalendarRelay")
                .apply { acquire(240_000) }
        }
        channel?.invokeMethod("dispatch", mapOf(
            "id" to "calendar-${++sequence}", "expiresAt" to postedAt + 30_000
        ), object : MethodChannel.Result {
            override fun success(result: Any?) { finished(result?.toString() ?: "Unknown outcome") }
            override fun error(code: String, message: String?, details: Any?) { finished("Failed: $code") }
            override fun notImplemented() { finished("Relay worker unavailable") }
        })
    }

    private fun finished(outcome: String) {
        saveOutcome("Calendar haptic: $outcome")
        pending--
        if (pending == 0) {
            handler.removeCallbacks(watchdog)
            releaseWakeLock()
            if (stopping) stopSelf()
        }
    }

    fun requestStop(reason: String) {
        stopping = true
        saveOutcome(reason)
        channel?.invokeMethod("close", null)
        if (pending == 0) stopSelf()
    }

    override fun onDestroy() {
        if (active === this) active = null
        handler.removeCallbacks(watchdog)
        channel?.setMethodCallHandler(null)
        channel = null
        engine?.destroy()
        engine = null
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    private fun saveOutcome(value: String) {
        getSharedPreferences("calendar_relay", MODE_PRIVATE).edit().putString("outcome", value).apply()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private var starting = false
        private var cancelStart = false

        fun start(context: Context) {
            if (active != null || starting) return
            starting = true
            cancelStart = false
            try {
                val intent = Intent(context, CalendarRelayService::class.java)
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                else context.startService(intent)
            } catch (error: Exception) {
                starting = false
                throw error
            }
        }

        fun stop() {
            if (starting) cancelStart = true
            active?.requestStop("Relay stopped.")
        }

        private const val CHANNEL = "calendar_relay"
        private const val STOP = "calendar_relay.STOP"
        var active: CalendarRelayService? = null
            private set

        fun hasAccess(context: Context): Boolean {
            val expected = ComponentName(context, CalendarNotificationListener::class.java)
            return Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
                ?.split(':')?.any { ComponentName.unflattenFromString(it) == expected } == true
        }

        fun status(context: Context): Map<String, Any?> = mapOf(
            "access" to hasAccess(context),
            "connected" to CalendarNotificationListener.connected,
            "running" to (active != null || starting),
            "stopping" to (active?.stopping == true),
            "outcome" to context.getSharedPreferences("calendar_relay", MODE_PRIVATE).getString("outcome", null)
        )
    }
}
