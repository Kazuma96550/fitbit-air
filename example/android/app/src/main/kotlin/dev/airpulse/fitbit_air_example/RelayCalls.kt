package dev.airpulse.fitbit_air_example

/**
 * Incoming-call vibrations. Selecting the phone app in the app list turns them on:
 * while the phone rings, the relay repeats a vibration until the call is answered,
 * rejected or missed. Pure decisions live here so they can be unit tested; the
 * telephony listener stays in [CalendarRelayService].
 */
internal object RelayCalls {
    /** Fallbacks when Android does not report a default phone app. */
    val knownDialers = listOf(
        "com.samsung.android.dialer",
        "com.google.android.dialer",
        "com.android.dialer",
    )

    /** Pause between the end of one vibration and the start of the next. */
    const val GAP_MILLIS = 1_500L

    /** A ringing phone stops vibrating the Air after this long. */
    const val LIMIT_MILLIS = 60_000L

    /** A vibration that cannot start within this window is dropped, not delayed. */
    const val EXPIRY_MILLIS = 10_000L

    /** The selected phone app that enables call vibrations, or null when none is selected. */
    fun dialer(selected: Set<String>, defaultDialer: String?): String? =
        (listOfNotNull(defaultDialer) + knownDialers).firstOrNull { it in selected }

    /** A vibration chosen for the phone app wins; otherwise two pulses. Null means muted. */
    fun preset(config: RelayRuleConfig, dialer: String): RelayPreset? {
        val preset = config.apps[dialer]?.preset ?: RelayPreset.DOUBLE
        return if (preset == RelayPreset.MUTE) null else preset
    }

    /** Whether a ring that started at [since] may still produce another vibration at [now]. */
    fun withinLimit(since: Long, now: Long): Boolean = now >= since && now - since < LIMIT_MILLIS
}
