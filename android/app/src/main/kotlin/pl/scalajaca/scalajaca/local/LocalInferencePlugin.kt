package pl.scalajaca.scalajaca.local

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/** Inferencja i import poza UI; bez serwera, sieci, usług tła i pobierania wag. */
class LocalInferencePlugin(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "pl.scalajaca/local_inference")
    private val executor = Executors.newSingleThreadExecutor()
    private val busy = globalBusy
    private val importCancelled = AtomicBoolean(false)
    private val serial = AtomicLong(0)
    private var token = 0L
    private var requestId: String? = null
    private var picker: MethodChannel.Result? = null
    private var expectedHash: String? = null
    @Volatile private var disposed = false
    @Volatile private var thermalStopped = false
    @Volatile private var importing = false
    private val store = LocalModelStore(File(activity.filesDir, "local_models"))

    init {
        if (busy.compareAndSet(false, true)) {
            try { store.cleanPartialImports() } finally { busy.set(false) }
        }
        channel.setMethodCallHandler(::handle)
    }
    private fun modelMap(model: LocalModelStore.Model) = mapOf(
        "id" to model.id, "name" to model.name, "profile" to model.profile,
        "bytes" to model.bytes, "sha256" to model.id,
    )
    private fun event(id: String, values: Map<String, Any>) {
        activity.runOnUiThread { if (!disposed) channel.invokeMethod("event", mapOf("requestId" to id) + values) }
    }
    private fun errorCode(ex: Exception): String {
        val known = setOf("invalid_gguf", "unsupported_model", "unsupported_quantization", "hash_mismatch", "invalid_hash", "file_too_large", "storage_space", "cancelled", "missing_model", "invalid_model_id")
        return ex.message?.takeIf { it in known } ?: "storage"
    }
    private fun hot(): Boolean = Build.VERSION.SDK_INT >= 29 &&
        (activity.getSystemService(Context.POWER_SERVICE) as PowerManager).currentThermalStatus >= PowerManager.THERMAL_STATUS_SEVERE

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "status" -> result.success(mapOf("engineCommit" to NativeLlama.version(), "models" to store.list().map(::modelMap)))
                "import" -> {
                    val expected = call.argument<String>("expectedSha256") ?: ""
                    require(expected.isEmpty() || expected.matches(Regex("[a-fA-F0-9]{64}")))
                    if (!busy.compareAndSet(false, true)) { result.error("busy", "Silnik lub import jest zajęty.", null); return }
                    picker = result; expectedHash = expected
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE); type = "*/*"
                    }
                    try { @Suppress("DEPRECATION") activity.startActivityForResult(intent, REQUEST_IMPORT) }
                    catch (ex: Exception) { busy.set(false); picker = null; throw ex }
                }
                "delete" -> {
                    if (!busy.compareAndSet(false, true)) { result.error("busy", "Najpierw zatrzymaj inferencję lub import.", null); return }
                    val id = call.argument<String>("model") ?: ""
                    executor.execute {
                        try { store.remove(id); activity.runOnUiThread { result.success(null) } }
                        catch (ex: Exception) { activity.runOnUiThread { result.error(errorCode(ex), "Nie udało się usunąć modelu.", null) } }
                        finally { busy.set(false) }
                    }
                }
                "generate" -> generate(call, result)
                "stop" -> {
                    val id = call.argument<String>("requestId")
                    if (id != null && id == requestId) NativeLlama.cancel(token)
                    result.success(null)
                }
                "cancelImport" -> { importCancelled.set(true); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (_: UnsatisfiedLinkError) { result.error("unsupported_abi", "Brak zgodnego silnika w tej wersji APK.", null)
        } catch (_: OutOfMemoryError) { result.error("memory", "Za mało pamięci urządzenia.", null)
        } catch (_: Exception) { result.error("invalid_request", "Nieprawidłowa operacja silnika lokalnego.", null) }
    }
    private fun generate(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("requestId") ?: throw IllegalArgumentException()
        val modelId = call.argument<String>("model") ?: throw IllegalArgumentException()
        val context = call.argument<Int>("context") ?: 2048
        val limit = call.argument<Int>("maxTokens") ?: 512
        val sourceGrounded = call.argument<Boolean>("sourceGrounded") ?: false
        val turns = call.argument<List<Map<String,String>>>("turns") ?: throw IllegalArgumentException()
        require(id.matches(Regex("[a-zA-Z0-9_-]{1,80}")) && context in 512..4096 && limit in 1..512 && limit < context && turns.size in 1..128)
        val messages = JSONArray()
        turns.forEach { turn ->
            require(turn["role"] in setOf("system", "user", "assistant") && turn["text"] != null)
            messages.put(JSONObject().put("role", turn["role"]).put("content", turn["text"]))
        }
        val json = messages.toString().toByteArray(Charsets.UTF_8); require(json.size <= 65536)
        val model = store.get(modelId)
        if (hot()) { result.error("thermal", "Urządzenie jest zbyt gorące. Poczekaj na schłodzenie.", null); return }
        val memory = ActivityManager.MemoryInfo()
        (activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
        if (memory.lowMemory || memory.availMem < model.bytes + 320L * 1024 * 1024) {
            result.error("memory", "Za mało wolnego RAM dla tego modelu. Zwolnij pamięć lub wybierz mniejszy GGUF.", null); return
        }
        if (!busy.compareAndSet(false, true)) { result.error("busy", "Silnik lub import jest zajęty.", null); return }
        try {
            token = serial.incrementAndGet(); requestId = id; thermalStopped = false
            val runToken = token
            NativeLlama.prepare(runToken) // Stop przed startem kolejki nie jest gubiony.
            executor.execute {
                try {
                    GgufInspector.inspect(store.modelFile(modelId)) { disposed || requestId != id }
                    val output = JSONObject(NativeLlama.generate(runToken, store.modelFile(modelId).absolutePath,
                        model.profile, json, context, limit, sourceGrounded, object : TokenSink {
                            override fun onBytes(bytes: ByteArray) {
                                if (hot()) { thermalStopped = true; NativeLlama.cancel(runToken) }
                                event(id, mapOf("type" to "bytes", "bytes" to bytes))
                            }
                        }))
                    if (thermalStopped) event(id, mapOf("type" to "error", "code" to "thermal"))
                    else if (output.has("error")) event(id, mapOf("type" to "error", "code" to output.getString("error")))
                    else event(id, mapOf("type" to "done", "reason" to output.getString("finish_reason"),
                        "inputTokens" to output.getInt("input_tokens"), "outputTokens" to output.getInt("output_tokens")))
                } catch (_: OutOfMemoryError) { event(id, mapOf("type" to "error", "code" to "memory"))
                } catch (ex: Exception) { event(id, mapOf("type" to "error", "code" to errorCode(ex)))
                } finally { busy.set(false) }
            }
            result.success(null)
        } catch (ex: UnsatisfiedLinkError) { busy.set(false); throw ex
        } catch (ex: OutOfMemoryError) { busy.set(false); throw ex
        } catch (ex: Exception) { busy.set(false); throw ex }
    }
    fun activityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != REQUEST_IMPORT) return false
        val result = picker ?: return true; picker = null
        val expected = expectedHash; expectedHash = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { busy.set(false); result.success(null); return true }
        importing = true; importCancelled.set(false)
        executor.execute {
            try {
                val model = activity.contentResolver.openInputStream(uri)?.use { input ->
                    store.importFrom(input, expected) { disposed || importCancelled.get() }
                } ?: throw IOException("storage")
                activity.runOnUiThread { result.success(modelMap(model)) }
            } catch (ex: Exception) { activity.runOnUiThread { result.error(errorCode(ex), "Import modelu nie został ukończony.", null) } }
            finally { importing = false; busy.set(false) }
        }
        return true
    }
    fun background() {
        if (requestId != null && busy.get() && !importing && picker == null) NativeLlama.cancel(token)
        if (importing) importCancelled.set(true)
    }
    fun close() {
        background()
        if (picker != null) { picker?.success(null); picker = null; busy.set(false) }
        disposed = true; channel.setMethodCallHandler(null); executor.shutdown()
    }
    companion object {
        const val REQUEST_IMPORT = 8103
        private val globalBusy = AtomicBoolean(false)
    }
}
