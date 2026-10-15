package dev.airpulse.fitbit_air

import com.fitbit.goldengate.bindings.coap.data.*
import io.reactivex.Single
import io.reactivex.subjects.PublishSubject
import java.util.LinkedList
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test

class AirRejectedRouteHandlerTest {
    private fun request(verb: Method, data: Single<ByteArray>) = object : IncomingRequest {
        override val method = verb
        override val options: Options = LinkedList()
        override val progressObserver = PublishSubject.create<Int>()
        override val body = object : IncomingBody {
            override fun asData() = data
        }
    }

    @Test fun `observes only metadata and rejects every method without executing an action`() {
        val events = mutableListOf<Map<String, Any>>()
        val handler = AirRejectedRouteHandler("md/1802", events::add)
        for (verb in Method.values()) {
            val request = request(verb, Single.just(byteArrayOf(10, 20, 30)))
            val builder = OutgoingResponseBuilder()
            val response = when (verb) {
                Method.GET -> handler.onGet(request, builder)
                Method.POST -> handler.onPost(request, builder)
                Method.PUT -> handler.onPut(request, builder)
                Method.DELETE -> handler.onDelete(request, builder)
            }.blockingGet()
            assertEquals(ResponseCode.notFound, response.responseCode)
            assertEquals(setOf("kind", "path", "method", "bodyLength", "receivedAtMillis"), events.last().keys)
            assertEquals(3, events.last()["bodyLength"])
            assertEquals(verb.name, events.last()["method"])
        }
    }

    @Test fun `decodes the secure event route while preserving rejection`() {
        val events = mutableListOf<Map<String, Any>>()
        val handler = AirRejectedRouteHandler("eventsSecure", events::add)
        val bytes = byteArrayOf(8, 0xab.toByte(), 0xe6.toByte(), 0xc9.toByte(), 0xbb.toByte(), 7)
        val response = handler.onPost(request(Method.POST, Single.just(bytes)),
            OutgoingResponseBuilder()).blockingGet()
        assertEquals(ResponseCode.notFound, response.responseCode)
        assertEquals(listOf(2003989291L), events.single()["eventIds"])
        assertEquals(listOf("WRS_ON"), events.single()["eventNames"])
        assertFalse(events.single().containsKey("payload"))
    }

    @Test fun `body failure still rejects and never exposes error contents`() {
        val events = mutableListOf<Map<String, Any>>()
        val handler = AirRejectedRouteHandler("md/1802", events::add)
        val response = handler.onPost(
            request(Method.POST, Single.error(IllegalStateException("private payload"))),
            OutgoingResponseBuilder(),
        ).blockingGet()
        assertEquals(ResponseCode.notFound, response.responseCode)
        assertTrue(events.isEmpty())
    }
}
