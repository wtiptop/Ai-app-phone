package pl.scalajaca.scalajaca.colibri

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream

class ColibriProtocolTest {
    private val ready = "\u0001\u0001READY\u0001\u0001\n"
    @Test fun byteFramingAndUsageMatchPinnedProtocol() {
        val writer = ByteArrayOutputStream()
        val out = ByteArrayOutputStream()
        val frames = ready + "STAT 0 0\nDATA app 5\na\nbcd\nDONE app STAT 1 3.0 0.0 0.01 12 0\n"
        val usage = ColibriProtocol.generate(ByteArrayInputStream(frames.toByteArray()), writer, "żółw".toByteArray(), 4) { out.write(it) }
        assertEquals("a\nbcd", out.toString("UTF-8"))
        assertTrue(writer.toString("UTF-8").startsWith("SUBMIT app 0 7 4 0 1\nżółw\n"))
        assertEquals(12, usage.input); assertEquals(1, usage.output); assertFalse(usage.limited)
    }
    @Test fun rejectsForeignIdsHugeFramesTruncationAndInvalidUsage() {
        val bad = listOf("DATA other 1\nx\n", "DATA app 999999999\n", "DATA app 3\nx",
            "DONE app STAT 999 1.0 0.0 0.0 2 0\n", "DATA app -1\n")
        for (frame in bad) {
            try {
                ColibriProtocol.generate(ByteArrayInputStream((ready + frame).toByteArray()), ByteArrayOutputStream(), "x".toByteArray(), 4) {}
                fail("Odrzuć ramkę")
            } catch (_: ColibriFailure) {}
        }
    }
    @Test fun contextErrorIsNotSuccess() {
        try {
            ColibriProtocol.generate(ByteArrayInputStream((ready + "ERROR app CONTEXT_EXCEEDED prompt_tokens=9000\n").toByteArray()), ByteArrayOutputStream(), "x".toByteArray(), 4) {}
            fail()
        } catch (e: ColibriFailure) { assertEquals("context_limit", e.code) }
    }
}
