package dev.airpulse.fitbit_air_example

import org.junit.Assert.*
import org.junit.Test

class RelayConversationPolicyTest {
    @Test fun unrestrictedModePreservesExistingAppsIncludingMissingMetadata() {
        for (pkg in listOf("com.whatsapp", "com.whatsapp.w4b", "com.google.android.calendar")) {
            assertTrue(RelayConversationPolicy.accepts(pkg, false, emptySet(), null))
        }
    }

    @Test fun restrictedModeFailsClosedForEmptyOrUnknownConversation() {
        for (pkg in RelayConversationPolicy.packages) {
            assertFalse(RelayConversationPolicy.accepts(pkg, true, emptySet(), "chat"))
            assertFalse(RelayConversationPolicy.accepts(pkg, true, setOf("chat"), null))
            assertFalse(RelayConversationPolicy.accepts(pkg, true, setOf("chat"), "other"))
            assertTrue(RelayConversationPolicy.accepts(pkg, true, setOf("chat"), "chat"))
        }
    }

    @Test fun restrictionDoesNotChangeOtherApps() {
        assertTrue(RelayConversationPolicy.accepts("com.google.android.calendar", true, emptySet(), null))
    }

    @Test fun selectedChatStillUsesFreshnessAndDuplicateFilter() {
        val filter = CalendarAlertFilter(1000, selectedPackages = setOf("com.whatsapp"))
        fun accept(key: String, time: Long, id: String?) =
            filter.accept("com.whatsapp", key, time, time, false, false, time) &&
                RelayConversationPolicy.accepts("com.whatsapp", true, setOf("alice"), id)
        assertTrue(accept("chat1", 1100, "alice"))
        assertFalse(accept("chat1", 1100, "alice"))
        assertTrue(accept("chat1", 1200, "alice"))
        assertFalse(accept("chat2", 1300, "bob"))
        assertFalse(accept("chat1", 900, "alice"))
        // Rejecting an unidentified update still consumes its timestamp.
        assertFalse(accept("chat3", 1400, null))
        assertFalse(accept("chat3", 1400, "alice"))
    }
}
