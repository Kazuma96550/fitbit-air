package dev.airpulse.fitbit_air_example

import android.app.Notification
import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

/** Opt-in local metadata capture. No message text is read, stored or exported. */
internal object RelayConversations {
    private data class Chat(val id: String, val packageName: String, val label: String) {
        fun toMap() = mapOf("id" to id, "packageName" to packageName, "label" to label)
    }
    private val candidates = linkedMapOf<String, Chat>()
    private var captureUntil = 0L
    private var captureStartedAt = 0L
    private var unsupported = 0
    private val handler = Handler(Looper.getMainLooper())
    private val expiry = Runnable { stopCapture() }
    private fun prefs(context: Context) = context.getSharedPreferences("relay_conversations", Context.MODE_PRIVATE)

    private fun saved(context: Context): List<Chat> = runCatching {
        val array = JSONArray(prefs(context).getString("allowed", "[]"))
        (0 until minOf(array.length(), 64)).map { index ->
            val item = array.getJSONObject(index)
            Chat(item.getString("id"), item.getString("packageName"), item.getString("label"))
        }
    }.getOrDefault(emptyList())

    private fun modePrefs(context: Context) = context.getSharedPreferences("calendar_relay", Context.MODE_PRIVATE)
    fun restricted(context: Context) = modePrefs(context).getBoolean("restricted_conversations", false)
    fun allowed(context: Context) = saved(context).map { it.id }.toSet()

    fun identity(packageName: String, notification: Notification): String? {
        if (packageName !in RelayConversationPolicy.packages || Build.VERSION.SDK_INT < 26) return null
        val shortcut = notification.shortcutId?.takeIf { it.isNotBlank() } ?: return null
        return MessageDigest.getInstance("SHA-256").digest("$packageName\u0000$shortcut".toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 255) }
    }

    fun capture(context: Context, enabled: Boolean) {
        check(!CalendarRelayService.isRunning) { "Stop the relay before capturing conversations." }
        if (enabled) {
            check(CalendarRelayService.hasAccess(context) && CalendarNotificationListener.connected) {
                "Enable notification access and wait for connection first."
            }
        }
        candidates.clear()
        unsupported = 0
        captureStartedAt = System.currentTimeMillis()
        handler.removeCallbacks(expiry)
        captureUntil = if (enabled) SystemClock.elapsedRealtime() + 60_000 else 0
        if (enabled) handler.postDelayed(expiry, 60_000)
    }

    fun stopCapture() {
        handler.removeCallbacks(expiry)
        captureUntil = 0
        candidates.clear()
        unsupported = 0
    }

    fun observe(packageName: String, notification: Notification, postedAt: Long, ongoing: Boolean) {
        if (SystemClock.elapsedRealtime() >= captureUntil) { candidates.clear(); return }
        if (packageName !in RelayConversationPolicy.packages || ongoing ||
            notification.flags and Notification.FLAG_GROUP_SUMMARY != 0 || postedAt < captureStartedAt) return
        val id = identity(packageName, notification)
        if (id == null) { unsupported = minOf(unsupported + 1, 100); return }
        // Shortcut labels/titles are presentation only, never identity. Never inspect EXTRA_TEXT/MESSAGES here.
        val label = (notification.extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)
            ?: notification.extras.getCharSequence(Notification.EXTRA_TITLE))?.toString()
            ?.filterNot { it.isISOControl() }?.take(120)?.takeIf { it.isNotBlank() }
            ?: "Conversation (name unavailable)"
        if (candidates.size < 32 || candidates.containsKey(id)) candidates[id] = Chat(id, packageName, label)
    }

    fun setRestricted(context: Context, enabled: Boolean) {
        modePrefs(context).edit().putBoolean("restricted_conversations", enabled).apply()
    }

    fun select(context: Context, id: String, enabled: Boolean) {
        val chats = saved(context).associateBy { it.id }.toMutableMap()
        if (enabled) {
            check(SystemClock.elapsedRealtime() < captureUntil) { "Capture a fresh notification first." }
            val chat = requireNotNull(candidates[id]) { "Capture a fresh notification first." }
            require(chats.size < 64 || id in chats) { "Select up to 64 conversations." }
            chats[id] = chat
        } else chats.remove(id)
        val array = JSONArray()
        chats.values.forEach { array.put(JSONObject(it.toMap())) }
        prefs(context).edit().putString("allowed", array.toString()).apply()
    }

    fun clear(context: Context) { prefs(context).edit().remove("allowed").apply(); stopCapture() }

    fun status(context: Context): Map<String, Any> {
        val remaining = maxOf(0, captureUntil - SystemClock.elapsedRealtime())
        if (remaining == 0L) candidates.clear()
        return mapOf("restricted" to restricted(context), "captureRemainingMillis" to remaining,
            "unsupported" to unsupported, "allowed" to saved(context).map { it.toMap() },
            "candidates" to candidates.values.map { it.toMap() })
    }
}
