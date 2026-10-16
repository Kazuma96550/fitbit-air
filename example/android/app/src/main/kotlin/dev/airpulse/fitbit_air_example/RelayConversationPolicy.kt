package dev.airpulse.fitbit_air_example

/** Exact conversation IDs only: never fall back to display names or message history. */
internal object RelayConversationPolicy {
    val packages = setOf("com.whatsapp", "com.whatsapp.w4b")

    fun accepts(packageName: String, restricted: Boolean, allowed: Set<String>, id: String?): Boolean =
        packageName !in packages || !restricted || (id != null && id in allowed)
}
