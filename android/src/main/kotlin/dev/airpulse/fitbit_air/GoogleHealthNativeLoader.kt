package dev.airpulse.fitbit_air

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import com.fitbit.goldengate.bindings.GoldenGate
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.zip.ZipFile

/**
 * Loads the compatible Golden Gate implementation from the user's installed
 * Google Health/Fitbit application. No Google binary is distributed by this
 * plugin or read from private app data.
 */
internal object GoogleHealthNativeLoader {
    private const val GOOGLE_HEALTH_PACKAGE = "com.fitbit.FitbitMobile"
    // Google Health uses APK signer rotation. Pin both certificates in the
    // verified signing lineage, not the Play source-stamp certificate.
    private val GOOGLE_HEALTH_CERT_SHA256 = listOf(
        "2cc914da5a849426c1b591e12f0a8adb042fa2feade3a4762845ce6bfadcf313",
        "fa6a198803aac1939fed6bab9295e5184c00966bf912f8c5faff26576cc770ff",
    )

    @Volatile
    private var initialized = false

    @Synchronized
    fun initialize(context: Context) {
        if (initialized) return
        val packageManager = context.packageManager
        val appInfo = if (Build.VERSION.SDK_INT >= 33) {
            packageManager.getApplicationInfo(
                GOOGLE_HEALTH_PACKAGE,
                PackageManager.ApplicationInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getApplicationInfo(GOOGLE_HEALTH_PACKAGE, 0)
        }
        val packageInfoFlags = if (Build.VERSION.SDK_INT >= 28) {
            PackageManager.GET_SIGNING_CERTIFICATES.toLong()
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES.toLong()
        }
        val packageInfo = if (Build.VERSION.SDK_INT >= 33) {
            packageManager.getPackageInfo(
                GOOGLE_HEALTH_PACKAGE,
                PackageManager.PackageInfoFlags.of(packageInfoFlags),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(GOOGLE_HEALTH_PACKAGE, packageInfoFlags.toInt())
        }
        require(isTrustedGoogleHealth(packageManager, packageInfo)) {
            "The installed Google Health package has an unexpected signing certificate."
        }
        val versionCode = if (Build.VERSION.SDK_INT >= 28) packageInfo.longVersionCode
        else @Suppress("DEPRECATION") packageInfo.versionCode.toLong()
        val cacheDir = File(context.codeCacheDir, "fitbit_air_native/$versionCode-${packageInfo.lastUpdateTime}")
        val library = File(cacheDir, "libxp.so")
        if (!library.isFile || library.length() == 0L) {
            extractLibrary(appInfo.sourceDir, appInfo.splitSourceDirs.orEmpty(), library)
        }
        library.setReadable(true, true)
        library.setWritable(false, false)
        library.setExecutable(true, true)
        GoldenGate.init(loggingEnabled = false, libPath = library)
        initialized = true
    }

    private fun isTrustedGoogleHealth(
        packageManager: PackageManager,
        packageInfo: android.content.pm.PackageInfo,
    ): Boolean {
        val expected = GOOGLE_HEALTH_CERT_SHA256.map { certificate -> certificate.hexToBytes() }
        if (Build.VERSION.SDK_INT >= 28 && expected.any { certificate ->
                packageManager.hasSigningCertificate(
                    GOOGLE_HEALTH_PACKAGE,
                    certificate,
                    PackageManager.CERT_INPUT_SHA256,
                )
            }
        ) return true
        @Suppress("DEPRECATION")
        return packageInfo.signatures.orEmpty().any { signature ->
            val digest = MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
            expected.any(digest::contentEquals)
        }
    }

    private fun extractLibrary(baseApk: String, splitApks: Array<out String>, destination: File) {
        val abiEntries = Build.SUPPORTED_ABIS.map { abi -> "lib/$abi/libxp.so" }
        val apks = splitApks.asList() + baseApk
        destination.parentFile?.mkdirs()
        val temporary = File(destination.parentFile, "libxp.so.tmp")
        for (apk in apks) {
            ZipFile(apk).use { zip ->
                val entry = abiEntries.firstNotNullOfOrNull(zip::getEntry) ?: return@use
                zip.getInputStream(entry).use { input ->
                    FileOutputStream(temporary).use { output -> input.copyTo(output) }
                }
                if (!temporary.renameTo(destination)) {
                    temporary.copyTo(destination, overwrite = true)
                    temporary.delete()
                }
                return
            }
        }
        throw IllegalStateException(
            "Google Health does not provide a compatible libxp.so for any supported device ABI.",
        )
    }

    private fun String.hexToBytes(): ByteArray =
        chunked(2).map { it.toInt(16).toByte() }.toByteArray()
}
