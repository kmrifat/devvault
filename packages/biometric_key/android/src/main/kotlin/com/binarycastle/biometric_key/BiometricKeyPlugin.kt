package com.binarycastle.biometric_key

import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Keeps a vault key behind a fingerprint (SPEC §9.1). An AES-256-GCM key in
 * the Android Keystore, usable once per strong-biometric prompt and
 * invalidated when the enrolled biometrics change, wraps the vault key; the
 * wrapped bytes live in app-private shared preferences (backups are off).
 *
 * Channel `devvault/biometric_key`. Errors carry a code and nothing else:
 * `gone` (enrolment changed or no key), `no-activity`, `keystore`,
 * `auth-<code>`.
 */
class BiometricKeyPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: FragmentActivity? = null

    private val prefs: SharedPreferences
        get() = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "devvault/biometric_key")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        // BiometricPrompt needs a FragmentActivity (MainActivity is a
        // FlutterFragmentActivity).
        activity = binding.activity as? FragmentActivity
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val vault = call.argument<String>("vault")
        val reason = call.argument<String>("reason") ?: ""
        when (call.method) {
            "biometry" -> result.success(biometry())
            "has" -> result.success(vault != null && has(vault))
            "save" -> {
                val key = call.argument<ByteArray>("key")
                if (vault == null || key == null) return fail(result, "bad-arguments")
                save(vault, key, reason, result)
            }
            "read" -> {
                if (vault == null) return fail(result, "bad-arguments")
                read(vault, reason, result)
            }
            "delete" -> {
                if (vault != null) delete(vault)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun biometry(): String? {
        val status = BiometricManager.from(context).canAuthenticate(BIOMETRIC_STRONG)
        if (status != BiometricManager.BIOMETRIC_SUCCESS) return null
        return if (context.packageManager.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)) {
            "fingerprint"
        } else {
            "biometrics"
        }
    }

    private fun has(vault: String): Boolean =
        prefs.contains(ctKey(vault)) && keyStore().containsAlias(alias(vault))

    /** Answers true once stored, false if the user cancels the prompt. */
    private fun save(vault: String, key: ByteArray, reason: String, result: Result) {
        delete(vault)
        val cipher = try {
            Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.ENCRYPT_MODE, createKey(alias(vault)))
            }
        } catch (e: Exception) {
            delete(vault)
            return fail(result, "keystore")
        }
        prompt(
            reason,
            cipher,
            result,
            onCancel = {
                delete(vault)
                result.success(false)
            },
        ) { unlocked ->
            val wrapped = unlocked.doFinal(key)
            prefs.edit()
                .putString(ivKey(vault), encode(unlocked.iv))
                .putString(ctKey(vault), encode(wrapped))
                .apply()
            result.success(true)
        }
    }

    /** Answers the key, or null if the user cancels the prompt. */
    private fun read(vault: String, reason: String, result: Result) {
        val iv = prefs.getString(ivKey(vault), null)
        val wrapped = prefs.getString(ctKey(vault), null)
        val secret = try {
            keyStore().getKey(alias(vault), null) as? SecretKey
        } catch (e: Exception) {
            null
        }
        if (iv == null || wrapped == null || secret == null) {
            delete(vault)
            return fail(result, "gone")
        }
        val cipher = try {
            Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.DECRYPT_MODE, secret, GCMParameterSpec(128, decode(iv)))
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            // The enrolled biometrics changed: the key is unusable by design.
            delete(vault)
            return fail(result, "gone")
        } catch (e: Exception) {
            return fail(result, "keystore")
        }
        prompt(reason, cipher, result, onCancel = { result.success(null) }) { unlocked ->
            result.success(unlocked.doFinal(decode(wrapped)))
        }
    }

    private fun delete(vault: String) {
        prefs.edit().remove(ivKey(vault)).remove(ctKey(vault)).apply()
        try {
            keyStore().deleteEntry(alias(vault))
        } catch (e: Exception) {
            // Nothing stored.
        }
    }

    /** Shows the strong-biometric prompt bound to [cipher]. */
    private fun prompt(
        reason: String,
        cipher: Cipher,
        result: Result,
        onCancel: () -> Unit,
        onSuccess: (Cipher) -> Unit,
    ) {
        val host = activity ?: return fail(result, "no-activity")
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(auth: BiometricPrompt.AuthenticationResult) {
                val unlocked = auth.cryptoObject?.cipher ?: return fail(result, "keystore")
                try {
                    onSuccess(unlocked)
                } catch (e: Exception) {
                    fail(result, "keystore")
                }
            }

            override fun onAuthenticationError(code: Int, message: CharSequence) {
                when (code) {
                    BiometricPrompt.ERROR_USER_CANCELED,
                    BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                    BiometricPrompt.ERROR_CANCELED -> onCancel()
                    else -> fail(result, "auth-$code")
                }
            }
            // onAuthenticationFailed is a scan that didn't match: the prompt
            // stays up for another try.
        }
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("DevVault")
            .setSubtitle(reason)
            .setNegativeButtonText("Use password")
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .build()
        BiometricPrompt(host, ContextCompat.getMainExecutor(context), callback)
            .authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }

    private fun createKey(alias: String): SecretKey {
        fun spec(strongBox: Boolean) =
            KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(true)
                .setInvalidatedByBiometricEnrollment(true)
                .apply {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
                    } else {
                        // -1: every use needs a fresh biometric prompt.
                        @Suppress("DEPRECATION")
                        setUserAuthenticationValidityDurationSeconds(-1)
                    }
                    if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        setIsStrongBoxBacked(true)
                    }
                }
                .build()

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        return try {
            generator.init(spec(strongBox = true))
            generator.generateKey()
        } catch (e: Exception) {
            // No StrongBox on this device: the TEE-backed Keystore.
            generator.init(spec(strongBox = false))
            generator.generateKey()
        }
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun fail(result: Result, code: String) = result.error(code, null, null)

    private fun alias(vault: String) = "devvault-biometric-$vault"
    private fun ivKey(vault: String) = "iv:$vault"
    private fun ctKey(vault: String) = "ct:$vault"
    private fun encode(bytes: ByteArray) = Base64.encodeToString(bytes, Base64.NO_WRAP)
    private fun decode(text: String) = Base64.decode(text, Base64.NO_WRAP)

    private companion object {
        const val PREFS = "devvault_biometric_key"
        const val KEYSTORE = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
