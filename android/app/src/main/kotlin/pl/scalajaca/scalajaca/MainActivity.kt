package pl.scalajaca.scalajaca

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import pl.scalajaca.scalajaca.local.LocalInferencePlugin
import pl.scalajaca.scalajaca.vault.VaultPlugin
import pl.scalajaca.scalajaca.backup.BackupFilePlugin
import pl.scalajaca.scalajaca.colibri.ColibriPlugin

/** Jednorazowe wybory SAF, bez szerokich uprawnień do plików. */
class MainActivity : FlutterActivity() {
    private var localInference: LocalInferencePlugin? = null
    private var colibri: ColibriPlugin? = null
    private var vault: VaultPlugin? = null
    private var backupFiles: BackupFilePlugin? = null
    private var pending: MethodChannel.Result? = null
    private var saveContent: String? = null
    private val maxBytes = 16 * 1024 * 1024

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        colibri = ColibriPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        backupFiles = BackupFilePlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        try { vault = VaultPlugin(this, flutterEngine.dartExecutor.binaryMessenger) }
        catch (_: Exception) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pl.scalajaca/vault")
                .setMethodCallHandler { _, result -> result.error("vault_error", "Pamięć lokalna jest niedostępna.", null) }
        }
        try { localInference = LocalInferencePlugin(this, flutterEngine.dartExecutor.binaryMessenger) }
        catch (_: Exception) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pl.scalajaca/local_inference")
                .setMethodCallHandler { _, result -> result.error("storage", "Magazyn modeli lokalnych jest niedostępny.", null) }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pl.scalajaca/files")
            .setMethodCallHandler { call, result ->
                if (pending != null && (call.method == "save" || call.method == "import")) {
                    result.error("busy", "Inna operacja na pliku jest jeszcze otwarta.", null)
                    return@setMethodCallHandler
                }
                try {
                    when (call.method) {
                        "share" -> {
                            val text = call.argument<String>("content") ?: ""
                            require(text.toByteArray(StandardCharsets.UTF_8).size <= maxBytes)
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, text)
                            }
                            startActivity(Intent.createChooser(intent, "Udostępnij wybrany tekst"))
                            result.success(null)
                        }
                        "save" -> {
                            check(pending == null)
                            val text = call.argument<String>("content") ?: ""
                            require(text.toByteArray(StandardCharsets.UTF_8).size <= maxBytes)
                            val name = call.argument<String>("name") ?: "scalajaca.txt"
                            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = if (name.endsWith(".json")) "application/json" else "text/plain"
                                putExtra(Intent.EXTRA_TITLE, name.replace('/', '_').replace('\\', '_'))
                            }
                            pending = result
                            saveContent = text
                            @Suppress("DEPRECATION")
                            startActivityForResult(intent, 8101)
                        }
                        "import" -> {
                            check(pending == null)
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*"
                                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/plain", "text/markdown", "application/json", "application/octet-stream"))
                            }
                            pending = result
                            @Suppress("DEPRECATION")
                            startActivityForResult(intent, 8102)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    pending = null
                    saveContent = null
                    result.error("file_error", "Nie można otworzyć systemowej operacji na pliku.", null)
                }
            }
    }

    @Deprecated("Platform callback supported by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (localInference?.activityResult(requestCode, resultCode, data) == true) return
        if (colibri?.activityResult(requestCode, resultCode, data) == true) return
        if (vault?.activityResult(requestCode, resultCode, data) == true) return
        if (backupFiles?.activityResult(requestCode, resultCode, data) == true) return
        if (requestCode != 8101 && requestCode != 8102) return
        val result = pending ?: return
        val content = saveContent
        pending = null
        saveContent = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
        Thread {
            try {
                if (requestCode == 8101) {
                    contentResolver.openOutputStream(uri, "wt")?.use {
                        it.write((content ?: "").toByteArray(StandardCharsets.UTF_8))
                    } ?: error("No output")
                    runOnUiThread { result.success(null) }
                } else {
                    val bytes = contentResolver.openInputStream(uri)?.use { stream ->
                        val out = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = stream.read(buffer)
                            if (count < 0) break
                            require(out.size() + count <= maxBytes)
                            out.write(buffer, 0, count)
                        }
                        out.toByteArray()
                    } ?: error("No input")
                    val decoder = StandardCharsets.UTF_8.newDecoder()
                        .onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT)
                    val text = decoder.decode(ByteBuffer.wrap(bytes)).toString()
                    runOnUiThread { result.success(text) }
                }
            } catch (_: Exception) {
                runOnUiThread { result.error("file_error", "Plik niedostępny, zbyt duży lub nie jest tekstem UTF-8.", null) }
            }
        }.start()
    }
    override fun onStop() {
        colibri?.background()
        localInference?.background()
        vault?.background()
        super.onStop()
    }

    override fun onDestroy() {
        colibri?.close()
        localInference?.close()
        vault?.close()
        backupFiles?.close()
        super.onDestroy()
    }
}
