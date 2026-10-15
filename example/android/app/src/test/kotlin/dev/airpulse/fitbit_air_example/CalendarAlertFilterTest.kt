package dev.airpulse.fitbit_air_example

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CalendarAlertFilterTest {
    private val calendar = "com.google.android.calendar"

    @Test fun ignoresOtherAppsSummariesOngoingAndOldAlerts() {
        val filter = CalendarAlertFilter(1_000)
        assertFalse(filter.accept("another.app", "other", 1_001, 1_010, false, false))
        assertFalse(filter.accept(calendar, "summary", 1_001, 1_010, false, true))
        assertFalse(filter.accept(calendar, "ongoing", 1_001, 1_010, true, false))
        assertFalse(filter.accept(calendar, "old", 999, 1_010, false, false))
        assertFalse(filter.accept(calendar, "expired", 1_001, 31_001, false, false))
        assertFalse(filter.accept(calendar, "future", 1_011, 1_010, false, false))
        assertTrue(filter.accept(calendar, "fresh", 1_001, 1_010, false, false))
    }

    @Test fun existingNotificationsRemainIgnoredWhenUpdatedAfterStart() {
        val filter = CalendarAlertFilter(1_000, listOf("already-present"))
        assertFalse(filter.accept(calendar, "already-present", 2_000, 2_010, false, false))
        assertTrue(filter.accept(calendar, "new-reminder", 2_000, 2_010, false, false))
    }

    @Test fun updatesCannotBuzzAgainEvenIfTimestampChanges() {
        val filter = CalendarAlertFilter(1_000)
        assertTrue(filter.accept(calendar, "same-key", 1_001, 1_010, false, false))
        assertFalse(filter.accept(calendar, "same-key", 2_000, 2_010, false, false))
        assertTrue(filter.accept(calendar, "different-key", 2_000, 2_010, false, false))
    }

    @Test fun boundedSessionNeverEvictsKeysAndReplaysOldAlerts() {
        val filter = CalendarAlertFilter(1_000)
        repeat(256) { assertTrue(filter.accept(calendar, "key-$it", 1_001, 1_010, false, false)) }
        assertFalse(filter.accept(calendar, "overflow", 1_001, 1_010, false, false))
        assertFalse(filter.accept(calendar, "key-0", 1_001, 1_010, false, false))
    }
}
