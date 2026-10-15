package dev.airpulse.fitbit_air_example

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class CalendarNotificationListener : NotificationListenerService() {
    override fun onListenerConnected() {
        instance = this
        connected = true
    }

    override fun onListenerDisconnected() {
        instance = null
        connected = false
        CalendarRelayService.active?.requestStop("Notification access disconnected. Start the relay again when access is available.")
    }

    override fun onDestroy() {
        instance = null
        connected = false
        CalendarRelayService.active?.requestStop("Notification listener stopped. Start the relay again when access is available.")
        super.onDestroy()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        CalendarRelayService.active?.onAlert(
            sbn.packageName, sbn.key, sbn.postTime, sbn.isOngoing,
            sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0
        )
    }

    companion object {
        private var instance: CalendarNotificationListener? = null

        fun existingCalendarKeys(): List<String> = instance?.activeNotifications
            ?.filter { it.packageName == "com.google.android.calendar" }
            ?.map { it.key } ?: emptyList()

        var connected = false
            private set
    }
}
