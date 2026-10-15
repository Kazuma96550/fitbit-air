package dev.airpulse.fitbit_air

import com.fitbit.goldengate.bindings.NativeReferenceCreationResult
import com.fitbit.goldengate.bindings.coap.CoapEndpoint
import com.fitbit.goldengate.bindings.coap.CoapGroupRequestFilter
import com.fitbit.goldengate.bindings.io.RxSource
import com.fitbit.goldengate.bindings.io.TxSink
import com.fitbit.goldengate.bindings.stack.Stack
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test
import java.lang.reflect.Modifier

/** Shape checks only: no native loading. Based on the inspected Google Health JNI ABI. */
class NativeBindingSignaturesTest {
    @Test fun `active native constructors return result objects not raw references`() {
        for (type in listOf(CoapEndpoint::class.java, CoapGroupRequestFilter::class.java,
                RxSource::class.java, TxSink::class.java, Stack::class.java)) {
            val method = type.declaredMethods.single { it.name == "create" }
            assertTrue(Modifier.isNative(method.modifiers))
            assertEquals(NativeReferenceCreationResult::class.java, method.returnType, type.name)
        }
    }

    @Test fun `filter mutation and destruction return checked result codes`() {
        val methods = CoapGroupRequestFilter::class.java.declaredMethods
        for (name in listOf("setGroup", "destroy")) {
            val method = methods.single { it.name == name }
            assertTrue(Modifier.isNative(method.modifiers))
            assertEquals(Int::class.javaPrimitiveType, method.returnType)
        }
    }
}
