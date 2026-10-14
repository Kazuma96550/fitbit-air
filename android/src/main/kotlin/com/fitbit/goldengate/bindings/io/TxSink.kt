// Copyright 2017-2020 Fitbit, Inc
// SPDX-License-Identifier: Apache-2.0

package com.fitbit.goldengate.bindings.io

import androidx.annotation.Keep
import androidx.annotation.VisibleForTesting
import com.fitbit.goldengate.bindings.GoldenGate
import com.fitbit.goldengate.bindings.NativeReference
import com.fitbit.goldengate.bindings.NativeReferenceCreationResult
import com.fitbit.goldengate.bindings.GoldenGateNativeException
import com.fitbit.goldengate.bindings.GoldenGateNativeResult
import com.fitbit.goldengate.bindings.util.hexString
import io.reactivex.Observable
import io.reactivex.subjects.PublishSubject
import timber.log.Timber
import java.io.Closeable

/**
 * TxSink is a DataSink for bottom on Golden Gate stack and DataSource for top of Native/Android
 * connection Bridge and is used to transmit data packets from GG stack to connected Node
 */
class TxSink : NativeReference, Closeable {

    private val dataSubject = PublishSubject.create<ByteArray>()

    override val thisPointer: Long

    /**
     * Data to be transmitted (over tx characteristics) will be available on this Observable
     */
    val dataObservable: Observable<ByteArray>
        get() = dataSubject

    init {
        GoldenGate.check()
        thisPointer = create(TxSink::class.java, "putData", "([B)I").validPointer("TxSink")
    }

    /**
     * This should only be called from the JNI code and in tests as it is the output from Gattlink
     * to be sent over BLE
     */
    @VisibleForTesting
    @Keep
    fun putData(data: ByteArray): Int {
        dataSubject.onNext(data)
        return GoldenGateNativeResult.GG_SUCCESS.code
    }

    override fun close() {
        destroy(thisPointer).throwIfError("TxSink.destroy")
    }

    private external fun create(clazz: Class<TxSink>, methodName: String, methodSignature: String): NativeReferenceCreationResult
    private external fun destroy(ptr: Long): Int
    protected external fun notifyListener(ptr: Long): Int

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
