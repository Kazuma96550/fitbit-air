package dev.airpulse.fitbit_air_example

import android.content.Context
import android.content.Intent

/** Host-app preferences, deliberately separate from the device-control package. */
internal object RelayAppSelection {
    private const val DEFAULT_APP = "com.google.android.calendar"

    fun selected(context: Context): Set<String> = context
        .getSharedPreferences("calendar_relay", Context.MODE_PRIVATE)
        .getStringSet("selected_apps", setOf(DEFAULT_APP))!!.toSet()

    fun save(context: Context, packages: Set<String>) {
        require(packages.size <= 64 && packages.all {
            it != context.packageName && it.matches(Regex("[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+"))
        }) { "Select up to 64 notification apps, excluding this demo." }
        context.getSharedPreferences("calendar_relay", Context.MODE_PRIVATE)
            .edit().putStringSet("selected_apps", packages).apply()
    }

    @Suppress("DEPRECATION")
    fun available(context: Context): List<Map<String, String>> {
        val manager = context.packageManager
        val apps = manager.queryIntentActivities(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0
        ).map { it.activityInfo.applicationInfo }
            .filter { it.packageName != context.packageName }
            .distinctBy { it.packageName }
            .associate { it.packageName to it.loadLabel(manager).toString() }.toMutableMap()
        // Keep saved selections visible even after an app is uninstalled.
        for (name in selected(context)) apps.putIfAbsent(name,
            if (name == DEFAULT_APP) "Google Calendar" else name)
        return apps.entries.sortedBy { it.value.lowercase() }
            .map { mapOf("packageName" to it.key, "label" to it.value) }
    }
}
