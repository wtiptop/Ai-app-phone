package pl.scalajaca.scalajaca.colibri

import android.app.ActivityManager
import android.content.Context
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Wyłącznie jawna próba pełnych, wcześniej zainstalowanych wag. Bez fixture. */
class ColibriFullModelDeviceTest {
    @Test fun realOfflineGenerationStopAndRestart() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val arguments = InstrumentationRegistry.getArguments()
        check(arguments.getString("fullModelTest") == "yes") { "Uruchom osobno z jawnym identyfikatorem pełnych wag." }
        val modelId = arguments.getString("modelSha256") ?: error("Brak SHA manifestu")
        check(Regex("[a-f0-9]{64}").matches(modelId))
        val store = ColibriModelStore(File(context.filesDir, "colibri_models"))
        val model = store.models().single { it["id"] == modelId }
        assertEquals("olmoe-instruct", model["profile"])
        val report = JSONObject().put("modelManifestSha256", modelId).put("syntheticWeights", false)
            .put("modelBytes", model["bytes"]).put("cases", JSONArray())
        val cases = report.getJSONArray("cases")
        val runId = arguments.getString("runId") ?: "test"
        check(Regex("[a-z0-9-]{1,40}").matches(runId))
        val output = File(context.filesDir, "colibri-full-$runId.json")
        check(!output.exists()) { "Nie nadpisujemy wcześniejszego raportu." }
        fun save() { output.writeText(report.toString(2)) }
        fun sample(): Long {
            val memory = ActivityManager.MemoryInfo()
            (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
            assertFalse(memory.lowMemory)
            assertTrue("Próg produkcyjny: 4GiB wolnego RAM", memory.availMem >= 4L * 1024 * 1024 * 1024)
            return memory.availMem
        }
        fun generate(name: String, limit: Int, stop: Boolean = false): JSONObject {
            val row = JSONObject().put("id", name).put("availableBefore", sample())
            cases.put(row); save()
            val runner = ColibriRunner(context)
            val bytes = ByteArrayOutputStream()
            val executor = Executors.newSingleThreadScheduledExecutor()
            val start = SystemClock.elapsedRealtime()
            var stopRequested: Long? = null
            val timeout = executor.schedule({ runner.stop() }, 180, TimeUnit.SECONDS)
            val prompt = "|||IP_ADDRESS|||<|user|>\nNapisz po polsku jedno krótkie zdanie o lesie.\n<|assistant|>\n".toByteArray(Charsets.UTF_8)
            try {
                val usage = runner.run(store.model(modelId), prompt, 4096, limit) {
                    bytes.write(it)
                    if (stop && stopRequested == null) {
                        stopRequested = SystemClock.elapsedRealtime()
                        runner.stop()
                    }
                }
                row.put("status", "complete").put("inputTokens", usage.input).put("outputTokens", usage.output).put("limited", usage.limited)
            } catch (e: Exception) {
                row.put("status", "error").put("code", (e as? ColibriFailure)?.code ?: e.javaClass.simpleName)
            } finally {
                timeout.cancel(false); executor.shutdownNow(); runner.close()
                row.put("output", bytes.toString("UTF-8")).put("elapsedMs", SystemClock.elapsedRealtime() - start)
                stopRequested?.let { row.put("stopToTerminalMs", SystemClock.elapsedRealtime() - it) }
                save()
            }
            return row
        }
        val first = generate("generation-pl", 48)
        assertEquals("complete", first.getString("status"))
        assertTrue(first.getString("output").isNotBlank())
        val stopped = generate("stop-after-first-token", 512, stop = true)
        assertEquals("cancelled", stopped.getString("code"))
        assertTrue("Stop powinien zakończyć proces w 5s", stopped.getLong("stopToTerminalMs") < 5000)
        assertTrue(stopped.getString("output").isNotEmpty())
        val restarted = generate("restart-after-stop", 8)
        assertEquals("complete", restarted.getString("status"))
        assertTrue(restarted.getString("output").isNotEmpty())
        report.put("finished", true); save()
    }
}
