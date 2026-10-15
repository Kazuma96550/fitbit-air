package dev.airpulse.fitbit_air

import com.fitbit.goldengate.bindings.coap.CoapEndpoint
import com.fitbit.goldengate.bindings.coap.CoapEndpointHandlerConfiguration
import com.fitbit.goldengate.bindings.coap.CoapGroupRequestFilterMode
import com.fitbit.goldengate.bindings.coap.data.IncomingRequest
import com.fitbit.goldengate.bindings.coap.data.OutgoingResponseBuilder
import com.fitbit.goldengate.bindings.coap.data.ResponseCode
import com.fitbit.goldengate.bindings.coap.handler.BaseResourceHandler
import io.reactivex.Single
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/** Device-to-phone EventSet: repeated uint32 field 1. No event is labeled a tap. */
internal object AirProtocolEventDecoder {
    private val names = mapOf(1920165236L to "RSET", 1651732067L to "BSNC",
        1667723379L to "CGPS", 1885957735L to "PING", 1634690668L to "AOFL",
        2003989291L to "WRS_ON", 2003989293L to "WRS_OFF")

    fun name(id: Long): String = names[id] ?: "UNKNOWN"

    fun decode(bytes: ByteArray): List<Long> {
        require(bytes.size <= 1024) { "Event payload exceeds diagnostic limit." }
        var position = 0
        fun varint(end: Int = bytes.size): Long {
            var value = 0L
            for (index in 0..9) {
                require(position < end) { "Truncated event varint." }
                val next = bytes[position++].toInt() and 255
                require(index != 9 || next <= 1) { "Invalid event varint." }
                value = value or ((next and 127).toLong() shl (index * 7))
                if (next and 128 == 0) return value
            }
            error("Invalid event varint.")
        }
        fun skip(count: Long) {
            require(count >= 0 && count <= bytes.size - position) { "Truncated event field." }
            position += count.toInt()
        }
        val ids = mutableListOf<Long>()
        fun add(id: Long) {
            require(id in 0..0xffffffffL && ids.size < 64) { "Invalid or excessive event IDs." }
            ids.add(id)
        }
        while (position < bytes.size) {
            val tag = varint()
            require(tag in 8..0xffffffffL) { "Invalid event field tag." }
            val field = tag ushr 3
            val wire = (tag and 7).toInt()
            if (field == 1L) {
                when (wire) {
                    0 -> add(varint())
                    2 -> {
                        val size = varint()
                        require(size >= 0 && size <= bytes.size - position) { "Truncated packed events." }
                        val end = position + size.toInt()
                        while (position < end) add(varint(end))
                    }
                    else -> throw IllegalArgumentException("Unexpected event field encoding.")
                }
            } else when (wire) {
                0 -> varint()
                1 -> skip(8)
                2 -> skip(varint())
                5 -> skip(4)
                else -> throw IllegalArgumentException("Unsupported event field encoding.")
            }
        }
        return ids
    }
}

/** Bounded local /events server; no outgoing setting/sync/reset commands. */
internal class AirSecureEventCapture(
    private val endpoint: CoapEndpoint,
    private val emit: (Map<String, Any>) -> Unit,
) {
    private val closed = AtomicBoolean(false)
    private val posts = AtomicInteger(0)
    private var registered = false

    fun start(): Single<Map<String, Any>> {
        val resource = object : BaseResourceHandler() {
            override fun onPost(request: IncomingRequest, responseBuilder: OutgoingResponseBuilder) =
                request.body.asData().map { bytes ->
                    val count = posts.incrementAndGet()
                    var code = ResponseCode.changed
                    if (!closed.get() && count <= 64) {
                        val event = mutableMapOf<String, Any>("receivedAtMillis" to System.currentTimeMillis())
                        try {
                            val ids = AirProtocolEventDecoder.decode(bytes)
                            event["kind"] = "device_event"
                            event["eventIds"] = ids
                            event["eventNames"] = ids.map(AirProtocolEventDecoder::name)
                        } catch (_: IllegalArgumentException) {
                            event["kind"] = "malformed_event"
                            code = ResponseCode.badRequest
                        }
                        emit(event)
                    }
                    responseBuilder.responseCode(code).build()
                }
        }
        return endpoint.addResourceHandler("events", resource,
            CoapEndpointHandlerConfiguration(CoapGroupRequestFilterMode.GROUP_1))
            .andThen(Single.defer {
                registered = true
                emit(mapOf("kind" to "ready", "durationSeconds" to 30,
                    "receivedAtMillis" to System.currentTimeMillis()))
                Single.timer(30, TimeUnit.SECONDS).map {
                    mapOf<String, Any>("receivedPosts" to posts.get(),
                        "droppedPosts" to (posts.get() - 64).coerceAtLeast(0))
                }
            })
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        if (registered) endpoint.removeResourceHandler("events").subscribe({}, {})
    }
}
