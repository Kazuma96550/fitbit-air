// Copyright 2017-2020 Fitbit, Inc
// SPDX-License-Identifier: Apache-2.0

package com.fitbit.goldengate.bindings.coap

import com.fitbit.goldengate.bindings.NativeReferenceWithCallback
import com.fitbit.goldengate.bindings.NativeReferenceCreationResult
import com.fitbit.goldengate.bindings.GoldenGateNativeException
import com.fitbit.goldengate.bindings.GoldenGateNativeResult
import com.fitbit.goldengate.bindings.util.isNotNull
import timber.log.Timber
import java.io.Closeable

/**
 * This class provides apis to setup/update CoAP request filters
 * group #1 is used for non-authenticated connections,
 * and group #0 (i.e. no filtering) is used for authenticated states.
 */
class CoapGroupRequestFilter : NativeReferenceWithCallback, Closeable {

    @get:Synchronized
    @set:Synchronized
    override var thisPointerWrapper: Long = 0

    override fun onFree() {
        thisPointerWrapper = 0
        Timber.d("free the native reference")
    }

    init {
        val created = create()
        if (!created.isSuccess) {
            throw GoldenGateNativeException("CoapGroupRequestFilter creation failed: ${created.result.title}", created.resultCode)
        }
        thisPointerWrapper = created.pointer
        this.setGroupTo(CoapGroupRequestFilterMode.GROUP_1)
    }

    /**
     * Set the current group mode for the CoAP request filter.
     * @param CoapGroupRequestFilterMode group number
     */
    fun setGroupTo(group: CoapGroupRequestFilterMode) {
        if (thisPointerWrapper.isNotNull()) {
            checkResult(setGroup(thisPointerWrapper, group.value), "setGroup")
        }
    }

    override fun close() {
        if (thisPointerWrapper.isNotNull()) {
            checkResult(destroy(thisPointerWrapper), "destroy")
        }
    }

    private fun checkResult(code: Int, operation: String) {
        val result = GoldenGateNativeResult.getNativeResultFrom(code)
        if (result != GoldenGateNativeResult.GG_SUCCESS) {
            throw GoldenGateNativeException("CoapGroupRequestFilter.$operation failed: ${result.title}", code)
        }
    }

    private external fun create(): NativeReferenceCreationResult

    private external fun setGroup(selfPtr: Long, group: Byte): Int

    private external fun destroy(selfPtr: Long): Int
}
