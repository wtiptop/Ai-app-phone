package pl.scalajaca.scalajaca.local

import android.os.SystemClock
import android.util.Base64
import android.util.Xml
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.xmlpull.v1.XmlPullParser
import java.io.File

/** Diagnostyka wyłącznie syntetycznej fixture własnego emulatora; bez logów prywatnych rozmów. */
class RecallDiagnosticsDeviceTest {
    @Test fun rawNativeRecallBeforeUi() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        val target = instrumentation.targetContext
        assertEquals("true", InstrumentationRegistry.getArguments().getString("scalajacaEmulator"))
        assertEquals("1", device.executeShellCommand("getprop ro.kernel.qemu").trim())
        assertEquals("Scalajaca_API30", device.executeShellCommand("getprop ro.kernel.qemu.avd_name").trim())
        assertEquals("1", device.executeShellCommand("settings get global airplane_mode_on").trim())
        val proof = File(target.filesDir,"emulator-proof")
        val parser = Xml.newPullParser()
        val inputFile = File(proof,"memory-late-fact-preview.xml")
        var packet: String? = null
        inputFile.reader().use { reader ->
            parser.setInput(reader)
            while (parser.eventType != XmlPullParser.END_DOCUMENT) {
                if (parser.eventType == XmlPullParser.START_TAG && parser.name == "node") {
                    val value = parser.getAttributeValue(null,"text").orEmpty()
                    if (value.startsWith("{\"format\":\"scalajaca.source-data.v1\"")) packet = value
                }
                parser.next()
            }
        }
        val source = JSONObject(packet ?: throw AssertionError("Brak syntetycznego podglądu"))
        val excerpt = source.getJSONArray("sources").getJSONObject(0)
        assertEquals("Archive.md",excerpt.getString("path"))
        assertTrue(excerpt.getString("text").startsWith("Archive section 22."))
        assertTrue(excerpt.getString("text").endsWith("The recovery key is COMPASS.\n"))
        assertEquals(1,source.getJSONArray("sources").length())
        val grounded=InstrumentationRegistry.getArguments().getString("grounded","true")=="true"
        val id="81b64d05a23b17b34c475f42b3e72fbde62d4b92cc34541f7a8031d0752deafa"
        val store=LocalModelStore(File(target.filesDir,"local_models"))
        val model=store.get(id)
        val trials=JSONArray()
        // Trzy identyczne próby oraz inne nazwy: brak specjalnego traktowania COMPASS.
        val expectedValues=if(grounded) listOf("COMPASS","COMPASS","COMPASS","LANTERN","RAVEN") else listOf("COMPASS","COMPASS","COMPASS")
        expectedValues.forEachIndexed { index, expected ->
            val messages=JSONArray().put(JSONObject().put("role","user").put("content",packet!!.replace("COMPASS",expected)))
                .put(JSONObject().put("role","user").put("content","Copy the recovery key from the provided source verbatim. Keep its exact spelling. Reply only with the key."))
            val token=95000L+index
            NativeLlama.prepare(token)
            val chunks=JSONArray(); val output=StringBuilder(); val began=SystemClock.elapsedRealtime()
            val result=JSONObject(NativeLlama.generate(token,store.modelFile(id).absolutePath,model.profile,
                messages.toString().toByteArray(Charsets.UTF_8),4096,32,grounded,object:TokenSink {
                    override fun onBytes(bytes:ByteArray) {
                        output.append(String(bytes,Charsets.UTF_8))
                        chunks.put(JSONObject().put("utf8",String(bytes,Charsets.UTF_8)).put("base64",Base64.encodeToString(bytes,Base64.NO_WRAP)))
                    }
                }))
            assertFalse(result.toString(),result.has("error"))
            assertEquals("stop",result.getString("finish_reason"))
            trials.put(result.put("rawOutput",output.toString()).put("expected",expected).put("chunks",chunks).put("elapsedMs",SystemClock.elapsedRealtime()-began))
            File(proof,"raw-recall-${if(grounded) "grounded" else "sampled"}.json").writeText(JSONObject().put("diagnosticOnly",!grounded)
                .put("sourceGrounded",grounded).put("beforeDartAndUi",true).put("trials",trials).toString(2))
            if(grounded) assertEquals("Zachowawczy tryb musi zachować dokładny fakt, próba $index",expected,output.toString().trim())
        }
        val connectivity=device.executeShellCommand("dumpsys connectivity")
        assertTrue(connectivity.contains("Active default network: none") || connectivity.contains("Active default network: null"))
    }
}
