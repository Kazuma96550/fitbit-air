package com.fitbit.goldengate.bindings

/** ABI-compatible result object returned by the newer libxp.so JNI constructors. */
data class NativeReferenceCreationResult(
    val resultCode: Int,
    val pointer: Long
) {
    val result: GoldenGateNativeResult = GoldenGateNativeResult.getNativeResultFrom(resultCode)
    val isSuccess: Boolean = result == GoldenGateNativeResult.GG_SUCCESS && pointer != 0L
}
