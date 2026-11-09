package de.klarblick.klarblick

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FragmentActivity ist für die Biometrie-Abfrage (local_auth) erforderlich.
class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    // Dateien, mit denen die App gestartet wurde („Teilen“ / „Öffnen mit“).
                    "takeInitialFiles" -> {
                        val files = readFiles(intent)
                        if (files.isNotEmpty()) consume()
                        result.success(files)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    // Die App läuft bereits und bekommt eine weitere Datei übergeben.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val files = readFiles(intent)
        if (files.isNotEmpty()) {
            consume()
            channel?.invokeMethod("incomingFiles", files)
        }
    }

    /** Verhindert, dass dieselbe Datei nach einem Neustart der Activity erneut importiert wird. */
    private fun consume() {
        setIntent(Intent(Intent.ACTION_MAIN))
    }

    private fun readFiles(intent: Intent?): List<Map<String, Any>> {
        if (intent == null) return emptyList()
        val uris = ArrayList<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                (intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))?.let { uris.add(it) }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.addAll(it) }
            }
            Intent.ACTION_VIEW -> intent.data?.let { uris.add(it) }
            else -> return emptyList()
        }
        // Manche Apps übergeben die Datei nur als ClipData.
        if (uris.isEmpty()) {
            val clip = intent.clipData
            if (clip != null) for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { uris.add(it) }
        }

        val out = ArrayList<Map<String, Any>>()
        for (uri in uris) {
            try {
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: continue
                if (bytes.isEmpty() || bytes.size > MAX_BYTES) continue
                out.add(mapOf("name" to displayName(uri), "bytes" to bytes))
            } catch (e: Exception) {
                // Nicht lesbar (Berechtigung entzogen o. Ä.) – diese Datei überspringen.
            }
        }
        // Reiner Text (z. B. CSV aus der Zwischenablage-Freigabe)
        if (out.isEmpty() && intent.action == Intent.ACTION_SEND) {
            intent.getStringExtra(Intent.EXTRA_TEXT)?.let { text ->
                val bytes = text.toByteArray(Charsets.UTF_8)
                if (bytes.isNotEmpty() && bytes.size <= MAX_BYTES) out.add(mapOf("name" to "Geteilter Text", "bytes" to bytes))
            }
        }
        return out
    }

    private fun displayName(uri: Uri): String {
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (i >= 0) c.getString(i)?.let { return it }
                }
            }
        } catch (e: Exception) {
        }
        return uri.lastPathSegment ?: "Datei"
    }

    companion object {
        const val CHANNEL = "de.klarblick.klarblick/incoming"
        private const val MAX_BYTES = 25 * 1024 * 1024
    }
}
