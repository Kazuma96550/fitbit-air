// Copyright 2017-2020 Fitbit, Inc
// SPDX-License-Identifier: Apache-2.0

package com.fitbit.goldengate.bindings.io

import androidx.annotation.AnyThread
import com.fitbit.goldengate.bindings.GoldenGate
import com.fitbit.goldengate.bindings.NativeReference
import com.fitbit.goldengate.bindings.NativeReferenceCreationResult
import com.fitbit.goldengate.bindings.GoldenGateNativeException
import com.fitbit.goldengate.bindings.GoldenGateNativeResult
import com.fitbit.goldengate.bindings.util.hexString
import io.reactivex.Completable
import timber.log.Timber
import java.io.Closeable

/**
 * RxSource is a DataSource for bottom on Golden Gate stack and DataSink for top of Native/Android
 * connection Bridge and is used to receive data packets to GG stack from connected Node
 */
class RxSource : NativeReference, Closeable {

    override val thisPointer: Long

    init {
        GoldenGate.check()
        thisPointer = create().validPointer("RxSource")
    }

    /**
     * Receive data from connected Node
     */
    @AnyThread
    fun receiveData(data: ByteArray): Completable {
        return Completable.fromCallable {
            // This jni call will post the message to the GG thread where the received data will be processed
            receiveData(data, thisPointer).throwIfError("RxSource.receiveData")
        }
    }

    override fun close() {
        destroy(thisPointer).throwIfError("RxSource.destroy")
    }

    private external fun receiveData(data: ByteArray, rxSourcePtr: Long): Int
    private external fun create(): NativeReferenceCreationResult
    private external fun destroy(source: Long): Int

    private fun NativeReferenceCreationResult.validPointer(operation: String): Long {
        if (isSuccess) return pointer
        throw GoldenGateNativeException("$operation failed: ${result.title}", resultCode)
    }

    private fun Int.throwIfError(operation: String) {
        val nativeResult = GoldenGateNativeResult.getNativeResultFrom(this)
        if (nativeResult != GoldenGateNativeResult.GG_SUCCESS) {
            throw GoldenGateNativeException("$operation failed: ${nativeResult.title}", this)
        }
    }
}
