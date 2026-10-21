package pl.scalajaca.scalajaca.colibri

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID

/** Sztuczne wagi przewidują ID 65. Testuje wierność C/JNI, nie jakość LLM. */
class ColibriTokenBufferDeviceTest {
    @Test fun full512ByteTokenSurvivesNativeDecodeAndFraming() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val directory = File(context.filesDir, "colibri-token-test-${UUID.randomUUID()}")
        assertTrue(directory.mkdirs())
        try {
            for (name in listOf("config.json", "tokenizer.json", "model.safetensors")) {
                instrumentation.context.assets.open("colibri-tiny/$name").use { input ->
                    File(directory, name).outputStream().use { input.copyTo(it) }
                }
            }
            val file = File(directory, "tokenizer.json")
            val tokenizer = JSONObject(file.readText())
            val vocab = tokenizer.getJSONObject("model").getJSONObject("vocab")
            assertEquals(65, vocab.getInt("A"))
            vocab.remove("A")
            // GPT-2 ByteLevel: U+0120 dekoduje się do jednej spacji 0x20.
            // Oficjalny tokenizer OLMoE zawiera taki token jako ID 19979.
            vocab.put("\u0120".repeat(512), 65)
            file.writeText(tokenizer.toString())
            val bytes = ByteArrayOutputStream()
            val prompt = "|||IP_ADDRESS|||<|user|>\nCześć\n<|assistant|>\n".toByteArray(Charsets.UTF_8)
            val usage = ColibriRunner(context).run(directory, prompt, 1024, 2) { bytes.write(it) }
            assertEquals(2, usage.output)
            assertTrue(usage.limited)
            assertEquals(1024, bytes.size())
            assertArrayEquals(ByteArray(1024) { 32 }, bytes.toByteArray())
        } finally {
            directory.deleteRecursively()
        }
    }
}
