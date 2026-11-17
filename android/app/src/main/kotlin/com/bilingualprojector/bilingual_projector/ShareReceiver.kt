package com.bilingualprojector.bilingual_projector

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Songs shared to the app ("Share → ChordPro Presenter" from Chrome, Files,
 * Gmail, a song site's app…) or opened with it ("Open with"): files (PDFs,
 * pictures, ChordPro, backups) and text (a song, or a link to one).
 *
 * Channel `bp/share`: the app calls `take` once it is ready, getting what
 * was shared before it started; after that each new share arrives as
 * `shared`. Each item is `{name, bytes}` for a file or `{text, subject}`.
 */
object ShareReceiver {
    private const val HANDLED = "bp.share.handled"
    private const val MAX_BYTES = 100L * 1024 * 1024

    private var channel: MethodChannel? = null
    private var ready = false
    private val pending = mutableListOf<Map<String, Any?>>()

    fun attach(engine: FlutterEngine) {
        ready = false
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "bp/share").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "take" -> {
                        ready = true
                        result.success(pending.toList())
                        pending.clear()
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** Reads what [intent] shares (once: a recreated activity skips it). */
    fun handle(activity: Activity, intent: Intent?) {
        if (intent == null || intent.getBooleanExtra(HANDLED, false)) return
        val items = read(activity, intent)
        if (items.isEmpty()) return
        intent.putExtra(HANDLED, true)
        val ch = channel
        if (ready && ch != null) {
            ch.invokeMethod("shared", items)
        } else {
            pending.addAll(items)
        }
    }

    private fun read(activity: Activity, intent: Intent): List<Map<String, Any?>> {
        val uris = mutableListOf<Uri>()
        var text: String? = null
        when (intent.action) {
            Intent.ACTION_SEND -> {
                stream(intent)?.let { uris.add(it) }
                if (uris.isEmpty()) text = intent.getStringExtra(Intent.EXTRA_TEXT)
            }
            Intent.ACTION_SEND_MULTIPLE -> uris.addAll(streams(intent))
            Intent.ACTION_VIEW -> intent.data?.let {
                // A remote control link, not a file.
                if (it.scheme == "chordpropresenter") text = it.toString() else uris.add(it)
            }
        }
        val out = mutableListOf<Map<String, Any?>>()
        for (uri in uris) {
            try {
                val name = nameOf(activity, uri)
                val bytes = activity.contentResolver.openInputStream(uri)?.use { input ->
                    val data = input.readBytes()
                    if (data.size > MAX_BYTES) null else data
                } ?: continue
                out.add(mapOf("name" to name, "bytes" to bytes))
            } catch (_: Exception) {
                // Unreadable (permission gone, a file too big…): skipped.
            }
        }
        if (!text.isNullOrBlank()) {
            out.add(mapOf("text" to text, "subject" to intent.getStringExtra(Intent.EXTRA_SUBJECT)))
        }
        return out
    }

    @Suppress("DEPRECATION")
    private fun stream(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    @Suppress("DEPRECATION")
    private fun streams(intent: Intent): List<Uri> =
        (if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }) ?: emptyList()

    private fun nameOf(activity: Activity, uri: Uri): String {
        try {
            activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { c ->
                    if (c.moveToFirst()) {
                        val name = c.getString(0)
                        if (!name.isNullOrBlank()) return name
                    }
                }
        } catch (_: Exception) {
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "Shared file"
    }
}
