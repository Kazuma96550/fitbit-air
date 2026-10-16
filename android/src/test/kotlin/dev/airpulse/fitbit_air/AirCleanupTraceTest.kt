package dev.airpulse.fitbit_air

import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test

class AirCleanupTraceTest {
    @Test fun `failed disconnect does not prevent close or expose exception text`() {
        val trace = AirCleanupTrace()
        var closed = false
        trace.step("gattDisconnect") { throw IllegalStateException("private device data") }
        trace.step("gattClose") { closed = true }
        trace.step("stack", false) { fail<Unit>("Absent resources must not be touched") }
        assertTrue(closed)
        assertEquals(mapOf("gattDisconnect" to "failed", "gattClose" to "returned", "stack" to "not_present"), trace.snapshot())
    }

    @Test fun `history is bounded and shared independently of engine ownership`() {
        repeat(20) { AirTransportDiagnostics.record("PreviewHaptic", mapOf("gattClose" to "returned")) }
        val owner = Any()
        assertTrue(AirTransportLease.tryAcquire(owner))
        try {
            assertEquals(true, AirTransportDiagnostics.snapshot()["appLeaseHeld"])
            assertEquals(16, (AirTransportDiagnostics.snapshot()["cleanupHistory"] as List<*>).size)
        } finally {
            AirTransportLease.release(owner)
        }
        assertEquals(false, AirTransportDiagnostics.snapshot()["appLeaseHeld"])
    }
}
