package dev.airpulse.fitbit_air_example

/** Metadata only: calendar titles, text and event contents are never inspected. */
internal class CalendarAlertFilter(private val startedAt: Long, existingKeys: List<String> = emptyList()) {
    private val seen = HashSet<String>(existingKeys.take(256))

    fun accept(packageName: String, key: String, postedAt: Long, now: Long,
               ongoing: Boolean, summary: Boolean): Boolean {
        if (packageName != "com.google.android.calendar" || ongoing || summary ||
            postedAt < startedAt || postedAt > now || now - postedAt >= 30_000 ||
            key in seen || seen.size >= 256) return false
        seen.add(key)
        return true
    }
}
