package pl.scalajaca.scalajaca.colibri

import android.content.Context
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.io.*
import java.util.UUID
import java.util.zip.*
import org.json.JSONObject

/** Dane syntetyczne, bez wytrenowanych wag: test portu, nie jakości LLM. */
class ColibriDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.targetContext
    private fun fixture(): File {
        val dir = File(context.filesDir, "colibri-test-${UUID.randomUUID()}").apply { mkdirs() }
        for (name in listOf("config.json", "tokenizer.json", "model.safetensors")) {
            instrumentation.context.assets.open("colibri-tiny/$name").use { input -> File(dir, name).outputStream().use { input.copyTo(it) } }
        }
        return dir
    }
    private val prompt = "|||IP_ADDRESS|||<|user|>\nCześć\n<|assistant|>\n".toByteArray()
    @Test fun offlineNativeGenerationFreshProcessAndUsage() {
        val dir = fixture()
        try {
            repeat(2) {
                val bytes = ByteArrayOutputStream()
                val usage = ColibriRunner(context).run(dir, prompt, 1024, 4) { bytes.write(it) }
                assertEquals("AAAA", bytes.toString("UTF-8")); assertEquals(4, usage.output)
                assertTrue(usage.input > 1); assertTrue(usage.limited)
            }
        } finally { dir.deleteRecursively() }
    }
    @Test fun stopAfterTokenAndRestart() {
        val dir = fixture()
        try {
            val runner = ColibriRunner(context)
            var tokens = 0
            val start = SystemClock.elapsedRealtime()
            try {
                runner.run(dir, prompt, 4096, 512) { tokens++; runner.stop() }
                fail("Stop nie może dać sukcesu")
            } catch (e: ColibriFailure) { assertEquals("cancelled", e.code) }
            assertTrue(tokens > 0); assertTrue(SystemClock.elapsedRealtime() - start < 15000)
            val next = ByteArrayOutputStream()
            ColibriRunner(context).run(dir, prompt, 1024, 2) { next.write(it) }
            assertEquals("AA", next.toString("UTF-8"))
        } finally { dir.deleteRecursively() }
    }
    @Test fun stopBeforeBindAndContextOverflow() {
        val runner = ColibriRunner(context)
        runner.stop()
        val dir = fixture()
        try {
            try { runner.run(dir, prompt, 1024, 2) {}; fail() }
            catch (e: ColibriFailure) { assertEquals("cancelled", e.code) }
            SystemClock.sleep(200)
            try { ColibriRunner(context).run(dir, ByteArray(1100) { 65 }, 1024, 2) {}; fail() }
            catch (e: ColibriFailure) { assertEquals("context_limit", e.code) }
        } finally { dir.deleteRecursively() }
    }
    @Test fun malformedModelDiesInWorkerAndAppCanGenerateAgain() {
        val dir = fixture()
        try {
            File(dir, "config.json").writeText("{}")
            try { ColibriRunner(context).run(dir, prompt, 1024, 2) {}; fail() }
            catch (_: ColibriFailure) {}
            SystemClock.sleep(300)
            val valid = fixture()
            try { assertEquals(2, ColibriRunner(context).run(valid, prompt, 1024, 2) {}.output) }
            finally { valid.deleteRecursively() }
        } finally { dir.deleteRecursively() }
    }
    private fun pkg() = instrumentation.context.assets.open("colibri-tiny/fixture.zip").use { it.readBytes() }
    private fun modified(manifest: JSONObject.() -> Unit = {}, extra: String? = null,
                         edit: ((String, ByteArray) -> ByteArray)? = null,
                         rawManifest: ((String) -> String)? = null): ByteArray {
        val original = mutableListOf<Pair<String, ByteArray>>()
        ZipInputStream(ByteArrayInputStream(pkg())).use { z ->
            while (true) { val entry = z.nextEntry ?: break; original.add(entry.name to z.readBytes()) }
        }
        val obj = JSONObject(String(original[0].second)).apply(manifest)
        if (edit != null) for (i in 1 until original.size) {
            val (name, raw) = original[i]
            val bytes = edit(name, raw)
            original[i] = name to bytes
            val files = obj.getJSONArray("files")
            for (j in 0 until files.length()) if (files.getJSONObject(j).getString("name") == name) {
                files.getJSONObject(j).put("bytes", bytes.size).put("sha256", ColibriModelStore.sha(bytes))
            }
        }
        val out = ByteArrayOutputStream()
        val manifestBytes = (rawManifest?.invoke(obj.toString()) ?: obj.toString()).toByteArray()
        ZipOutputStream(out).use { z ->
            for ((name, bytes) in original) {
                z.putNextEntry(ZipEntry(name)); z.write(if (name == "manifest.json") manifestBytes else bytes); z.closeEntry()
            }
            if (extra != null) { z.putNextEntry(ZipEntry(extra)); z.write(65); z.closeEntry() }
        }
        return out.toByteArray()
    }
    @Test fun installAtomicHashCancelTraversalAndProductionProfileGuard() {
        val root = File(context.filesDir, "colibri-store-test-${UUID.randomUUID()}")
        val store = ColibriModelStore(root, allowTestModels = true)
        try {
            val installed = store.install(ByteArrayInputStream(pkg()), "") { false }
            val id = installed["id"] as String
            assertEquals(1, store.models().size)
            val orphan = File(root, ".import-${UUID.randomUUID()}").apply { mkdirs() }
            File(orphan, "partial").writeText("partial")
            store.cleanPartialImports()
            assertFalse(orphan.exists()); assertEquals(1, store.models().size)
            assertEquals("synthetic-test", installed["profile"])
            assertEquals(2, ColibriRunner(context).run(store.model(id), prompt, 1024, 2) {}.output)
            fun rejected(bytes: ByteArray, hash: String = "", cancel: Boolean = false) {
                try { store.install(ByteArrayInputStream(bytes), hash) { cancel }; fail() }
                catch (_: ColibriFailure) {}
                assertEquals(1, store.models().size)
                assertEquals(0, root.listFiles()!!.count { it.name.startsWith(".import-") })
            }
            rejected(pkg(), "0".repeat(64))
            rejected(pkg(), cancel = true)
            rejected(modified({ getJSONArray("files").getJSONObject(0).put("sha256", "0".repeat(64)) }))
            rejected(modified(extra = "../escape.txt"))
            rejected(modified({ getJSONArray("files").put(getJSONArray("files").getJSONObject(0)) }))
            rejected(modified(edit = { name, bytes -> if (name == "tokenizer.json")
                JSONObject(String(bytes)).apply { getJSONObject("model").getJSONObject("vocab").put("A", 90000) }.toString().toByteArray() else bytes }))
            val production = mapOf("hidden_size" to 2048, "num_hidden_layers" to 16,
                "num_attention_heads" to 16, "num_key_value_heads" to 16, "num_experts" to 64,
                "num_experts_per_tok" to 8, "intermediate_size" to 1024, "vocab_size" to 50304)
            for (escaped in listOf(false, true)) {
                val crafted = modified({ put("profile", "olmoe-instruct") }, edit = { name, bytes ->
                    if (name == "config.json") {
                        val keys = production.entries.joinToString(",") { (k, v) ->
                            val key = if (escaped && k == "hidden_size") "\\u0068idden_size" else k
                            "\"$key\":$v"
                        }
                        (String(bytes).dropLast(1) + "," + keys + "}").toByteArray()
                    } else bytes
                })
                try { ColibriModelStore(root).install(ByteArrayInputStream(crafted), "") { false }; fail() }
                catch (e: ColibriFailure) { assertEquals("invalid_package", e.code) }
            }
            val nul = modified({ put("profile", "olmoe-instruct") }, edit = { name, bytes ->
                if (name == "config.json") {
                    val first = JSONObject(String(bytes))
                    val shadow = first.keys().asSequence().filter { it in production.keys }.joinToString(",") { "\"${it}\\u0000suffix\":${first.get(it)}" }
                    ("{" + shadow + "," + JSONObject(String(bytes)).apply { production.forEach { (k,v) -> put(k,v) } }.toString().drop(1)).toByteArray()
                } else bytes
            })
            try { ColibriModelStore(root).install(ByteArrayInputStream(nul), "") { false }; fail() }
            catch (e: ColibriFailure) { assertEquals("invalid_package", e.code) }
            // 20 KiB zagnieżdżenia: nie może przepełnić stosu parsera w procesie UI.
            rejected(modified(rawManifest = { it.dropLast(1) + ",\"unused\":" + "[".repeat(10000) + "0" + "]".repeat(10000) + "}" }))
            rejected(modified(edit = { name, bytes ->
                if (name == "tokenizer.json") (String(bytes).dropLast(1) + ",\"unused\":[" + "0,".repeat(250001) + "0]}").toByteArray() else bytes
            }))
            try { ColibriModelStore(root).install(ByteArrayInputStream(pkg()), "") { false }; fail() }
            catch (e: ColibriFailure) { assertEquals("unsupported_model", e.code) }
            assertFalse(File(root.parentFile, "escape.txt").exists())
            store.remove(id); assertTrue(store.models().isEmpty())
        } finally { root.deleteRecursively() }
    }
}
