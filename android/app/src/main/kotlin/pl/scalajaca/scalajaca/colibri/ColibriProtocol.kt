package pl.scalajaca.scalajaca.colibri

import java.io.InputStream
import java.io.OutputStream

class ColibriFailure(val code: String) : Exception(code)

/** Ograniczony parser binarnych ramek: treść nigdy nie jest linią sterującą. */
object ColibriProtocol {
    data class Usage(val input: Int, val output: Int, val limited: Boolean)
    private fun line(input: InputStream): String {
        val out = java.io.ByteArrayOutputStream()
        while (true) {
            val byte = input.read()
            if (byte < 0) throw ColibriFailure("model_load")
            if (byte == 10) return out.toString("UTF-8")
            if (out.size() >= 65536) throw ColibriFailure("protocol")
            out.write(byte)
        }
    }
    fun generate(input: InputStream, output: OutputStream, prompt: ByteArray,
                 maxTokens: Int, onBytes: (ByteArray) -> Unit): Usage {
        require(prompt.size in 1..65536 && maxTokens in 1..512)
        var bootLines = 0
        while (line(input) != "\u0001\u0001READY\u0001\u0001") {
            if (++bootLines > 256) throw ColibriFailure("protocol")
        }
        output.write("SUBMIT app 0 ${prompt.size} $maxTokens 0 1\n".toByteArray())
        output.write(prompt); output.write(10); output.flush()
        var total = 0
        var frames = 0
        while (++frames <= 20000) {
            val header = line(input)
            val fields = header.split(' ')
            when (fields[0]) {
                "DATA" -> {
                    if (fields.size != 3 || fields[1] != "app") throw ColibriFailure("protocol")
                    val size = fields[2].toIntOrNull() ?: throw ColibriFailure("protocol")
                    if (size !in 0..4096 || total + size > 1024 * 1024) throw ColibriFailure("protocol")
                    val bytes = ByteArray(size)
                    var read = 0
                    while (read < size) {
                        val n = input.read(bytes, read, size - read)
                        if (n <= 0) throw ColibriFailure("interrupted")
                        read += n
                    }
                    if (input.read() != 10) throw ColibriFailure("protocol")
                    total += size; onBytes(bytes)
                }
                "DONE" -> {
                    if (fields.size != 9 || fields[1] != "app" || fields[2] != "STAT") throw ColibriFailure("protocol")
                    val count = fields[3].toIntOrNull() ?: throw ColibriFailure("protocol")
                    val used = fields[7].toIntOrNull() ?: throw ColibriFailure("protocol")
                    val limited = fields[8].toIntOrNull() ?: throw ColibriFailure("protocol")
                    if (count !in 0..maxTokens || used !in 1..4096 || limited !in 0..1) throw ColibriFailure("protocol")
                    return Usage(used, count, limited == 1)
                }
                "ERROR" -> throw ColibriFailure(if (header.contains("CONTEXT_EXCEEDED")) "context_limit" else "model_load")
                // Ograniczone metadane upstream są odrzucane, nigdy logowane.
            }
        }
        throw ColibriFailure("protocol")
    }
}
