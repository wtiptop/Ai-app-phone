package pl.scalajaca.scalajaca.colibri

import org.json.JSONObject

import java.io.*
import java.security.MessageDigest
import java.util.UUID
import java.util.zip.ZipInputStream

/** Paczka danych, bez kodu i bez ścieżek z archiwum. Commit dopiero po weryfikacji. */
class ColibriModelStore(private val root: File, private val allowTestModels: Boolean = false) {
    companion object {
        const val COMMIT = "e0db083cdc9e563e0766cc6fc661ef23c32298e0"
        const val MAX_TOTAL = 10L * 1024 * 1024 * 1024
        private const val RESERVE = 512L * 1024 * 1024
        private val idPattern = Regex("[a-f0-9]{64}")
        private val filePattern = Regex("(config\\.json|tokenizer\\.json|model(-[0-9]{5}(-of-[0-9]{5})?)?\\.safetensors)")
        fun sha(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    }
    init { check(root.isDirectory || root.mkdirs()) }
    /** Wywoływane wyłącznie po przejęciu globalnej blokady importu. */
    fun cleanPartialImports() {
        val pattern = Regex("\\.import-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
        root.listFiles().orEmpty().filter { pattern.matches(it.name) && it.canonicalFile.parentFile == root.canonicalFile }
            .forEach { if (!it.deleteRecursively()) throw ColibriFailure("storage") }
    }
    private fun directory(id: String): File {
        if (!idPattern.matches(id)) throw ColibriFailure("invalid_model_id")
        return File(root, id)
    }
    private fun manifest(bytes: ByteArray): JSONObject {
        if (bytes.size > 65536) throw ColibriFailure("invalid_package")
        val text = String(bytes, Charsets.UTF_8)
        uniqueKeys(text)
        val data = JSONObject(text)
        if (data.getInt("format") != 1 || data.getString("engineCommit") != COMMIT ||
            data.getString("profile") !in (if (allowTestModels) listOf("olmoe-instruct", "synthetic-test") else listOf("olmoe-instruct")) ||
            data.getString("name").length !in 1..100 || data.getString("source").length !in 1..300) throw ColibriFailure("unsupported_model")
        val files = data.getJSONArray("files")
        if (files.length() !in 3..128) throw ColibriFailure("invalid_package")
        val names = mutableSetOf<String>()
        var total = 0L
        for (i in 0 until files.length()) {
            val f = files.getJSONObject(i)
            val name = f.getString("name")
            val size = f.getLong("bytes")
            if (!filePattern.matches(name) || !names.add(name) || size !in 1..MAX_TOTAL ||
                !idPattern.matches(f.getString("sha256"))) throw ColibriFailure("invalid_package")
            if (name == "config.json" && size > 256 * 1024) throw ColibriFailure("invalid_package")
            if (name == "tokenizer.json" && size > 8 * 1024 * 1024) throw ColibriFailure("invalid_package")
            total += size
            if (total > MAX_TOTAL) throw ColibriFailure("file_too_large")
        }
        if (!names.containsAll(listOf("config.json", "tokenizer.json")) || names.none { it.endsWith(".safetensors") }) throw ColibriFailure("invalid_package")
        return data
    }
    private fun bounded(input: InputStream, max: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            if (out.size() + n > max) throw ColibriFailure("invalid_package")
            out.write(buffer, 0, n)
        }
        return out.toByteArray()
    }
    fun install(input: InputStream, expected: String, cancelled: () -> Boolean): Map<String, Any> {
        if (expected.isNotEmpty() && !idPattern.matches(expected)) throw ColibriFailure("invalid_hash")
        val stage = File(root, ".import-${UUID.randomUUID()}")
        check(stage.mkdir())
        try {
            ZipInputStream(BufferedInputStream(input)).use { zip ->
                if (zip.nextEntry?.name != "manifest.json") throw ColibriFailure("invalid_package")
                val bytes = bounded(zip, 65536)
                val id = sha(bytes)
                if (expected.isNotEmpty() && expected != id) throw ColibriFailure("hash_mismatch")
                val data = manifest(bytes)
                val entries = data.getJSONArray("files")
                var total = 0L
                for (i in 0 until entries.length()) total += entries.getJSONObject(i).getLong("bytes")
                if (root.usableSpace < total + RESERVE) throw ColibriFailure("storage_space")
                val remaining = (0 until entries.length()).associate { i ->
                    val entry = entries.getJSONObject(i); entry.getString("name") to entry
                }.toMutableMap()
                while (true) {
                    if (cancelled()) throw ColibriFailure("cancelled")
                    val entry = zip.nextEntry ?: break
                    val spec = remaining.remove(entry.name) ?: throw ColibriFailure("invalid_package")
                    if (entry.isDirectory) throw ColibriFailure("invalid_package")
                    val digest = MessageDigest.getInstance("SHA-256")
                    val size = spec.getLong("bytes")
                    var read = 0L
                    FileOutputStream(File(stage, entry.name)).use { out ->
                        val buffer = ByteArray(256 * 1024)
                        while (true) {
                            if (cancelled()) throw ColibriFailure("cancelled")
                            val count = zip.read(buffer)
                            if (count < 0) break
                            read += count
                            if (read > size) throw ColibriFailure("invalid_package")
                            if (root.usableSpace < RESERVE) throw ColibriFailure("storage_space")
                            digest.update(buffer, 0, count); out.write(buffer, 0, count)
                        }
                        out.fd.sync()
                    }
                    val hash = digest.digest().joinToString("") { "%02x".format(it) }
                    if (read != size || hash != spec.getString("sha256")) throw ColibriFailure("hash_mismatch")
                }
                if (remaining.isNotEmpty()) throw ColibriFailure("invalid_package")
                validateConfig(stage, data.getString("profile"))
                validateTokenizer(stage, if (data.getString("profile") == "synthetic-test") 257 else 50304)
                FileOutputStream(File(stage, "manifest.json")).use { it.write(bytes); it.fd.sync() }
                if (cancelled()) throw ColibriFailure("cancelled")
                val dest = directory(id)
                if (dest.exists()) return info(id)
                if (!stage.renameTo(dest)) throw ColibriFailure("storage")
                return info(id)
            }
        } finally { stage.deleteRecursively() } // stage jest stałym dzieckiem prywatnego root
    }
    private fun validateConfig(dir: File, profile: String) {
        val text = File(dir, "config.json").readText()
        uniqueKeys(text)
        val config = JSONObject(text)
        val expected = if (profile == "synthetic-test" && allowTestModels)
            mapOf("hidden_size" to 16, "num_hidden_layers" to 1, "num_attention_heads" to 2,
                "num_key_value_heads" to 2, "num_experts" to 2, "num_experts_per_tok" to 1,
                "intermediate_size" to 8, "vocab_size" to 257)
        else mapOf("hidden_size" to 2048, "num_hidden_layers" to 16, "num_attention_heads" to 16,
            "num_key_value_heads" to 16, "num_experts" to 64, "num_experts_per_tok" to 8,
            "intermediate_size" to 1024, "vocab_size" to 50304)
        if (config.optString("model_type") != "olmoe" || expected.any { (k,v) -> config.opt(k) !is Number || config.optDouble(k) != v.toDouble() }) throw ColibriFailure("unsupported_model")
    }
    /** C wybiera pierwszy klucz, Android ostatni. Nie dopuszczamy tej rozbieżności. */
    private fun uniqueKeys(text: String) {
        try {
            android.util.JsonReader(StringReader(text)).use { reader ->
                reader.isLenient = false
                var nodes = 0
                var names = 0
                fun value(depth: Int) {
                    if (depth > 64 || ++nodes > 250000) throw ColibriFailure("invalid_package")
                    when (reader.peek()) {
                        android.util.JsonToken.BEGIN_OBJECT -> {
                            reader.beginObject()
                            val keys = mutableSetOf<String>()
                            while (reader.hasNext()) {
                                val key = reader.nextName()
                                if (++names > 100000 || key.length > 16384 || key.contains('\u0000') || !keys.add(key) || keys.size > 60000) throw ColibriFailure("invalid_package")
                                value(depth + 1)
                            }
                            reader.endObject()
                        }
                        android.util.JsonToken.BEGIN_ARRAY -> {
                            reader.beginArray()
                            while (reader.hasNext()) value(depth + 1)
                            reader.endArray()
                        }
                        android.util.JsonToken.STRING, android.util.JsonToken.NUMBER -> {
                            val text = reader.nextString()
                            if (text.length > 16384 || text.contains('\u0000')) throw ColibriFailure("invalid_package")
                        }
                        android.util.JsonToken.BOOLEAN -> { reader.nextBoolean() }
                        android.util.JsonToken.NULL -> reader.nextNull()
                        else -> throw ColibriFailure("invalid_package")
                    }
                }
                value(0)
                if (reader.peek() != android.util.JsonToken.END_DOCUMENT) throw ColibriFailure("invalid_package")
            }
        } catch (_: Exception) { throw ColibriFailure("invalid_package") }
    }
    private fun validateTokenizer(dir: File, vocab: Int) {
        val text = File(dir, "tokenizer.json").readText()
        uniqueKeys(text)
        val tokenizer = JSONObject(text)
        val model = tokenizer.getJSONObject("model")
        if (model.optString("type") != "BPE") throw ColibriFailure("unsupported_model")
        fun token(value: Any) {
            val id = (value as? Number)?.toDouble() ?: throw ColibriFailure("invalid_package")
            if (!id.isFinite() || id < 0 || id >= vocab || id != id.toInt().toDouble()) throw ColibriFailure("invalid_package")
        }
        val dictionary = model.getJSONObject("vocab")
        if (dictionary.length() !in 1..vocab) throw ColibriFailure("invalid_package")
        dictionary.keys().forEach { token(dictionary.get(it)) }
        val added = tokenizer.optJSONArray("added_tokens")
        if (added != null) {
            if (added.length() > vocab) throw ColibriFailure("invalid_package")
            for (n in 0 until added.length()) token(added.getJSONObject(n).get("id"))
        }
    }
    fun info(id: String): Map<String, Any> {
        val dir = directory(id)
        val file = File(dir, "manifest.json")
        if (!file.isFile || file.length() > 65536) throw ColibriFailure("missing_model")
        val bytes = file.readBytes()
        if (sha(bytes) != id) throw ColibriFailure("hash_mismatch")
        val data = manifest(bytes)
        var size = 0L
        val files = data.getJSONArray("files")
        for (i in 0 until files.length()) {
            val f = files.getJSONObject(i)
            val actual = File(dir, f.getString("name"))
            if (!actual.isFile || actual.length() != f.getLong("bytes")) throw ColibriFailure("missing_model")
            size += actual.length()
        }
        return mapOf("id" to id, "name" to data.getString("name"), "profile" to data.getString("profile"), "bytes" to size)
    }
    fun models(): List<Map<String, Any>> = root.listFiles().orEmpty().filter { it.isDirectory && idPattern.matches(it.name) }.mapNotNull {
        try { info(it.name) } catch (_: Exception) { null }
    }
    fun model(id: String): File { info(id); return directory(id) }
    fun remove(id: String) { if (!directory(id).deleteRecursively()) throw ColibriFailure("storage") }
}
