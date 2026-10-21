package pl.scalajaca.scalajaca.colibri

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.*
import io.flutter.plugin.common.*
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class ColibriPlugin(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "pl.scalajaca/colibri")
    private val store = ColibriModelStore(File(activity.filesDir, "colibri_models"))
    private val executor = Executors.newSingleThreadExecutor()
    private val busy = globalBusy
    private val cancelledImport = AtomicBoolean()
    private val handler = Handler(Looper.getMainLooper())
    private data class PendingImport(val result: MethodChannel.Result, val hash: String)
    private var picker: PendingImport? = null
    @Volatile private var run: ColibriRunner? = null
    @Volatile private var requestId: String? = null
    @Volatile private var disposed = false
    @Volatile private var cleanupFailed = false
    private fun error(result: MethodChannel.Result, e: Exception) = activity.runOnUiThread {
        result.error((e as? ColibriFailure)?.code ?: "storage", "Operacja Colibri nie została ukończona.", null)
    }
    private fun event(id: String, values: Map<String, Any>) = activity.runOnUiThread {
        if (!disposed) channel.invokeMethod("event", values + ("requestId" to id))
    }
    private fun hot(): Boolean = Build.VERSION.SDK_INT >= 29 &&
        (activity.getSystemService(Context.POWER_SERVICE) as PowerManager).currentThermalStatus >= PowerManager.THERMAL_STATUS_SEVERE
    init {
        if (busy.compareAndSet(false, true)) executor.execute {
            try { store.cleanPartialImports() } catch (_: Exception) { cleanupFailed = true } finally { busy.set(false) }
        }
        channel.setMethodCallHandler(::handle)
    }
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "status" -> result.success(mapOf("engineCommit" to ColibriModelStore.COMMIT, "models" to store.models()))
                "import" -> {
                    if (cleanupFailed) throw ColibriFailure("storage")
                    val expected = (call.argument<String>("expectedSha256") ?: "").lowercase()
                    if (expected.isNotEmpty() && !Regex("[a-f0-9]{64}").matches(expected)) throw ColibriFailure("invalid_hash")
                    if (!busy.compareAndSet(false, true)) throw ColibriFailure("busy")
                    picker = PendingImport(result, expected); cancelledImport.set(false)
                    try {
                        @Suppress("DEPRECATION")
                        activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            type = "*/*"; addCategory(Intent.CATEGORY_OPENABLE)
                        }, IMPORT)
                    } catch (e: Exception) { busy.set(false); picker = null; throw e }
                }
                "cancelImport" -> { cancelledImport.set(true); result.success(null) }
                "delete" -> {
                    if (!busy.compareAndSet(false, true)) throw ColibriFailure("busy")
                    executor.execute {
                        try { store.remove(call.argument<String>("model") ?: ""); activity.runOnUiThread { result.success(null) } }
                        catch (e: Exception) { error(result, e) }
                        finally { busy.set(false) }
                    }
                }
                "generate" -> generate(call, result)
                "stop" -> {
                    if (call.argument<String>("requestId") == requestId) run?.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) { error(result, e) }
    }
    private fun generate(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("requestId") ?: throw ColibriFailure("invalid_request")
        val model = call.argument<String>("model") ?: throw ColibriFailure("invalid_request")
        val context = call.argument<Int>("context") ?: 4096
        val limit = call.argument<Int>("maxTokens") ?: 512
        val prompt = call.argument<ByteArray>("prompt") ?: throw ColibriFailure("invalid_request")
        if (!Regex("[a-zA-Z0-9_-]{1,80}").matches(id) || context !in listOf(1024,2048,4096) || limit !in 1..512 || prompt.size !in 1..65536) throw ColibriFailure("invalid_request")
        val dir = store.model(model)
        if (hot()) throw ColibriFailure("thermal")
        val memory = ActivityManager.MemoryInfo()
        (activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
        // Resident dense f32 + 2 cache slots/layer + KV + rezerwa. To warunek wstępny, nie pomiar szczytu.
        if (memory.lowMemory || memory.availMem < 4L * 1024 * 1024 * 1024) throw ColibriFailure("memory")
        if (!busy.compareAndSet(false, true)) throw ColibriFailure("busy")
        val runner = ColibriRunner(activity.applicationContext)
        run = runner; requestId = id
        val started = SystemClock.elapsedRealtime()
        var stoppedReason: String? = null
        val monitor = object : Runnable {
            override fun run() {
                if (run !== runner) return
                stoppedReason = when {
                    hot() -> "thermal"
                    SystemClock.elapsedRealtime() - started >= 180000 -> "timeout"
                    else -> null
                }
                if (stoppedReason != null) runner.stop() else handler.postDelayed(this, 1000)
            }
        }
        handler.post(monitor)
        executor.execute {
            try {
                val usage = runner.run(dir, prompt, context, limit) { event(id, mapOf("type" to "bytes", "bytes" to it)) }
                event(id, mapOf("type" to "done", "reason" to if (usage.limited) "length" else "stop",
                    "inputTokens" to usage.input, "outputTokens" to usage.output))
            } catch (e: Exception) { event(id, mapOf("type" to "error", "code" to (stoppedReason ?: (e as? ColibriFailure)?.code ?: "model_load"))) }
            finally { runner.close(); handler.removeCallbacks(monitor); run = null; requestId = null; busy.set(false) }
        }
        result.success(null)
    }
    fun activityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != IMPORT) return false
        val selection = picker ?: return true
        val result = selection.result
        picker = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { busy.set(false); result.success(null); return true }
        executor.execute {
            try {
                val model = activity.contentResolver.openInputStream(uri)?.use {
                    store.install(it, selection.hash) { disposed || cancelledImport.get() }
                } ?: throw ColibriFailure("storage")
                activity.runOnUiThread { result.success(model) }
            } catch (_: OutOfMemoryError) { error(result, ColibriFailure("memory"))
            } catch (e: Exception) { error(result, e) }
            finally { busy.set(false) }
        }
        return true
    }
    fun background() { run?.stop(); if (picker == null) cancelledImport.set(true) }
    fun close() {
        disposed = true; background()
        picker?.let { it.result.success(null); busy.set(false) }; picker = null
        executor.shutdown(); channel.setMethodCallHandler(null)
    }
    companion object { private const val IMPORT = 8471; private val globalBusy = AtomicBoolean() }
}
