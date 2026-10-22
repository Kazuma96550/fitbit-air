package dev.airpulse.fitbit_air_example

import org.junit.Assert.*
import org.junit.Test

class RelayCallsTest {
    private val samsung = "com.samsung.android.dialer"

    @Test fun defaultPhoneAppEnablesCallsWhenSelected() {
        assertEquals("com.example.phone", RelayCalls.dialer(setOf("com.example.phone"), "com.example.phone"))
    }

    @Test fun knownPhoneAppCountsWithoutDefault() {
        assertEquals(samsung, RelayCalls.dialer(setOf(samsung, "com.whatsapp"), null))
    }

    @Test fun noPhoneAppSelectedMeansNoCallVibration() {
        assertNull(RelayCalls.dialer(setOf("com.whatsapp"), samsung))
        assertNull(RelayCalls.dialer(emptySet(), null))
    }

    @Test fun callsDefaultToTwoPulses() {
        val config = RelayRuleConfig(apps = mapOf(samsung to RelayAppRule(true)))
        assertEquals(RelayPreset.DOUBLE, RelayCalls.preset(config, samsung))
    }

    @Test fun phoneAppVibrationWins() {
        val config = RelayRuleConfig(apps = mapOf(samsung to RelayAppRule(true, RelayPreset.HIGH)))
        assertEquals(RelayPreset.HIGH, RelayCalls.preset(config, samsung))
    }

    @Test fun mutedPhoneAppStaysSilent() {
        val config = RelayRuleConfig(apps = mapOf(samsung to RelayAppRule(true, RelayPreset.MUTE)))
        assertNull(RelayCalls.preset(config, samsung))
    }

    @Test fun ringStopsVibratingAfterLimit() {
        assertTrue(RelayCalls.withinLimit(1_000, 1_000))
        assertTrue(RelayCalls.withinLimit(1_000, 1_000 + RelayCalls.LIMIT_MILLIS - 1))
        assertFalse(RelayCalls.withinLimit(1_000, 1_000 + RelayCalls.LIMIT_MILLIS))
        assertFalse(RelayCalls.withinLimit(1_000, 999))
    }
}
