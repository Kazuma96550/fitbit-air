package dev.airpulse.fitbit_air

import com.fitbit.goldengate.bindings.coap.CoapEndpoint
import com.fitbit.goldengate.bindings.coap.CoapEndpointHandlerConfiguration
import com.fitbit.goldengate.bindings.coap.CoapGroupRequestFilterMode
import com.fitbit.goldengate.bindings.coap.data.IncomingRequest
import com.fitbit.goldengate.bindings.coap.data.OutgoingResponseBuilder
import com.fitbit.goldengate.bindings.coap.data.OutgoingResponse
import com.fitbit.goldengate.bindings.coap.data.ResponseCode
import com.fitbit.goldengate.bindings.coap.handler.BaseResourceHandler
import io.reactivex.Single
import io.reactivex.Completable
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

/** Observe a previously unimplemented route, retaining its 4.04 response. */
internal class AirRejectedRouteHandler(
    private val path: String,
    private val emit: (Map<String, Any>) -> Unit,
) : BaseResourceHandler() {
    private fun reject(request: IncomingRequest, builder: OutgoingResponseBuilder): Single<OutgoingResponse> =
        request.body.asData().map { bytes ->
            val event = mutableMapOf<String, Any>("kind" to "unhandled_request", "path" to path,
                "method" to request.method.name, "bodyLength" to bytes.size,
                "receivedAtMillis" to System.currentTimeMillis())
            // Google Health uses the same EventSet decoder for both routes.
            // Decode known event IDs without changing the rejection response.
            if (path == "eventsSecure" && request.method == com.fitbit.goldengate.bindings.coap.data.Method.POST) {
                try {
                    val ids = AirProtocolEventDecoder.decode(bytes)
                    event["eventIds"] = ids
                    event["eventNames"] = ids.map(AirProtocolEventDecoder::name)
                } catch (_: IllegalArgumentException) {
                    event["decodeError"] = "INVALID_EVENT_SET"
                }
            }
            emit(event)
            builder.responseCode(ResponseCode.notFound).build()
        }.onErrorReturn { builder.responseCode(ResponseCode.notFound).build() }

    override fun onGet(request: IncomingRequest, responseBuilder: OutgoingResponseBuilder) = reject(request, responseBuilder)
    override fun onPost(request: IncomingRequest, responseBuilder: OutgoingResponseBuilder) = reject(request, responseBuilder)
    override fun onPut(request: IncomingRequest, responseBuilder: OutgoingResponseBuilder) = reject(request, responseBuilder)
    override fun onDelete(request: IncomingRequest, responseBuilder: OutgoingResponseBuilder) = reject(request, responseBuilder)
}

/** Bounded incoming-request observation; no outgoing setting/sync/reset commands. */
internal class AirSecureEventCapture(
    private val endpoint: CoapEndpoint,
    private val emit: (Map<String, Any>) -> Unit,
) {
    private val closed = AtomicBoolean(false)
    private val posts = AtomicInteger(0)
    private val registered = mutableListOf<String>()
    private val otherRequests = AtomicInteger(0)
    @Volatile private var readyAtNanos: Long? = null

    fun summary(): Map<String, Any> = mapOf(
        "receivedPosts" to posts.get(),
        "droppedPosts" to (posts.get() - 64).coerceAtLeast(0),
        "otherRequests" to otherRequests.get(),
        "droppedOtherRequests" to (otherRequests.get() - 32).coerceAtLeast(0),
        "observationMillis" to (readyAtNanos?.let {
            TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - it)
        } ?: 0L),
    )

    fun start(): Single<Map<String, Any>> {
        val resource = object : BaseResourceHandler() {
            override fun onPost(request: IncomingRequest, responseBuilder: OutgoingResponseBuilder) =
                request.body.asData().map { bytes ->
                    val count = posts.incrementAndGet()
                    var code = ResponseCode.changed
                    if (!closed.get() && count <= 64) {
                        val event = mutableMapOf<String, Any>("receivedAtMillis" to System.currentTimeMillis())
                        event["path"] = "events"
                        event["method"] = "POST"
                        event["bodyLength"] = bytes.size
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
        // Source-traced phone-side routes, NOT tracker endpoints to request.
        // These observers reject requests; registering them does not establish
        // normal paired authorization or claim the protected route is supported.
        val handlers = mapOf("events" to resource) + listOf(
            "eventsSecure", "sync/request", "md/3d02", "md/1802", "sb/reply", "sb/delete-records"
        ).associateWith { path -> AirRejectedRouteHandler(path) { event ->
            if (!closed.get() && otherRequests.incrementAndGet() <= 32) emit(event)
        } }
        return Completable.concat(handlers.map { (path, resourceHandler) ->
            endpoint.addResourceHandler(path, resourceHandler,
                CoapEndpointHandlerConfiguration(CoapGroupRequestFilterMode.GROUP_1))
                .doOnComplete { registered.add(path) }
        })
            .andThen(Single.defer {
                readyAtNanos = System.nanoTime()
                emit(mapOf("kind" to "ready", "durationSeconds" to 30,
                    "receivedAtMillis" to System.currentTimeMillis()))
                Single.timer(30, TimeUnit.SECONDS).map {
                    summary()
                }
            })
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        registered.forEach { endpoint.removeResourceHandler(it).subscribe({}, {}) }
        registered.clear()
    }
}
