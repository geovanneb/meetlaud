package com.meetlaud.app.infra.system

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import com.meetlaud.app.R
import com.meetlaud.domain.DeviceAuthenticator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

/**
 * Face, fingerprint, or the screen lock code, as SystemAuthenticator.swift does with Face ID and the passcode (D-061).
 * The system's own prompt: the app never sees a fingerprint or a code. The activity on screen registers itself.
 */
class SystemAuthenticator(private val context: Context) : DeviceAuthenticator {
    var activity: Activity? = null

    override val isAvailable: Boolean
        get() = context.getSystemService(KeyguardManager::class.java).isDeviceSecure

    override suspend fun authenticate(reason: String): Boolean = withContext(Dispatchers.Main) {
        val activity = activity ?: return@withContext false
        suspendCancellableCoroutine { continuation ->
            val cancel = CancellationSignal()
            continuation.invokeOnCancellation { cancel.cancel() }
            val builder = BiometricPrompt.Builder(activity).setTitle(activity.getString(R.string.app_name)).setSubtitle(reason)
            if (Build.VERSION.SDK_INT >= 30) {
                builder.setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK or BiometricManager.Authenticators.DEVICE_CREDENTIAL)
            } else {
                @Suppress("DEPRECATION")
                builder.setDeviceCredentialAllowed(true)
            }
            builder.build().authenticate(cancel, activity.mainExecutor, object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult?) {
                    if (continuation.isActive) continuation.resume(true)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) {
                    if (continuation.isActive) continuation.resume(false)
                }
            })
        }
    }
}
