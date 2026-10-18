package pl.scalajaca.scalajaca.local

import androidx.annotation.Keep

@Keep
interface TokenSink { fun onBytes(bytes: ByteArray) }

@Keep
object NativeLlama {
    init { System.loadLibrary("scalajaca_llama") }
    external fun version(): String
    external fun prepare(token: Long)
    external fun cancel(token: Long)
    external fun generate(token: Long, path: String, profile: String, messages: ByteArray, context: Int, limit: Int, sink: TokenSink): String
}
