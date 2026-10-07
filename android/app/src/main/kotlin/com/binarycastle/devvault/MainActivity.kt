package com.binarycastle.devvault

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

// FlutterFragmentActivity is required by local_auth / biometric prompts.
//
// Files other apps hand to DevVault (a VIEW or SEND intent: "Open with",
// "Share") are copied into a fresh cache folder each and their paths kept
// until Dart takes them on the devvault/incoming_files channel (P3-03).
class MainActivity : FlutterFragmentActivity() {
    private val pending = mutableListOf<String>()
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "devvault/incoming_files",
        ).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "take") {
                    result.success(ArrayList(pending))
                    pending.clear()
                } else {
                    result.notImplemented()
                }
            }
        }
        receive(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receive(intent)
    }

    private fun receive(intent: Intent?) {
        val uris: List<Uri> = when (intent?.action) {
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            Intent.ACTION_SEND -> listOfNotNull(streamExtra(intent))
            Intent.ACTION_SEND_MULTIPLE -> streamListExtra(intent)
            else -> emptyList()
        }
        val paths = uris.mapNotNull(::copyIn)
        if (paths.isEmpty()) return
        // Handled: don't import the same intent again on rotation.
        intent?.action = null
        pending.addAll(paths)
        channel?.invokeMethod("available", null)
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        intent.getParcelableExtra(Intent.EXTRA_STREAM)

    @Suppress("DEPRECATION")
    private fun streamListExtra(intent: Intent): List<Uri> =
        intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()

    private fun copyIn(uri: Uri): String? = try {
        val name = displayName(uri)?.substringAfterLast('/')?.ifBlank { null } ?: "file"
        val dir = File(cacheDir, "devvault-incoming-${UUID.randomUUID()}").apply { mkdirs() }
        val dest = File(dir, name)
        val input = contentResolver.openInputStream(uri) ?: return null
        input.use { source -> dest.outputStream().use { source.copyTo(it) } }
        dest.path
    } catch (e: Exception) {
        null
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme == "content") {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor -> if (cursor.moveToFirst()) return cursor.getString(0) }
        }
        return uri.lastPathSegment
    }
}
