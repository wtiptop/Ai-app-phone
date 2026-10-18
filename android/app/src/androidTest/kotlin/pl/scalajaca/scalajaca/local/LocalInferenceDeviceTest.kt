package pl.scalajaca.scalajaca.local

import android.content.Intent
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Configurator
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.After
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.Rule
import org.junit.rules.TestName
import org.junit.runners.MethodSorters
import java.io.File

/** Standardowy AndroidJUnitRunner; rzeczywisty APK i plik modelu, bez atrap JNI. */
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class LocalInferenceDeviceTest {
    @get:Rule val testName = TestName()
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val target = instrumentation.targetContext
    private val device = UiDevice.getInstance(instrumentation)
    private val expectedHash = "81b64d05a23b17b34c475f42b3e72fbde62d4b92cc34541f7a8031d0752deafa"
    private val proofDir by lazy { File(target.filesDir, "emulator-proof").apply { mkdirs() } }

    @Before fun emulatorOnlyAndOffline() {
        assertEquals("Test dotyczy wyłącznie własnego emulatora", "1", device.executeShellCommand("getprop ro.kernel.qemu").trim())
        assertEquals("Wymagane jawne uruchomienie scenariusza", "true", InstrumentationRegistry.getArguments().getString("scalajacaEmulator"))
        Configurator.getInstance().waitForIdleTimeout = 0
        assertEquals("Tryb samolotowy", "1", device.executeShellCommand("settings get global airplane_mode_on").trim())
        val connectivity = device.executeShellCommand("dumpsys connectivity")
        File(proofDir, "connectivity.txt").writeText(connectivity)
        assertTrue("Emulator ma aktywną sieć", connectivity.contains("Active default network: none") || connectivity.contains("Active default network: null"))
    }

    private fun visible(node: UiObject2) = node.visibleBounds.let { it.width() > 1 && it.height() > 1 }
    private fun find(label: String): UiObject2? = (device.findObjects(By.text(label)) + device.findObjects(By.desc(label))).firstOrNull(::visible)
    private fun containing(label: String): UiObject2? = (device.findObjects(By.textContains(label)) + device.findObjects(By.descContains(label))).firstOrNull(::visible)
    private fun waitFor(label: String, timeout: Long = 30000, contains: Boolean = false): UiObject2 {
        val end = SystemClock.elapsedRealtime() + timeout
        do {
            val found = if (contains) containing(label) else find(label)
            if (found != null && found.visibleBounds.height() > 0) return found
            SystemClock.sleep(200)
        } while (SystemClock.elapsedRealtime() < end)
        checkpoint("failure-${testName.methodName}")
        throw AssertionError("Nie znaleziono elementu: $label")
    }
    private fun click(label: String, contains: Boolean = false) {
        waitFor(label, contains = contains)
        // Węzeł jest widoczny już podczas animacji wysuwanego menu.
        SystemClock.sleep(350)
        waitFor(label, contains = contains).click()
        SystemClock.sleep(200)
    }
    private fun scrollTo(label: String): UiObject2 {
        repeat(12) {
            val found = find(label) ?: containing(label)
            if (found != null && found.visibleBounds.height() > 0) return found
            device.swipe(device.displayWidth / 2, device.displayHeight * 4 / 5, device.displayWidth / 2, device.displayHeight / 3, 30)
        }
        return waitFor(label, contains = true)
    }
    @After fun remainsOffline() {
        val connectivity = device.executeShellCommand("dumpsys connectivity")
        File(proofDir, "offline-after-${testName.methodName}.txt").writeText(connectivity)
        assertEquals("1", device.executeShellCommand("settings get global airplane_mode_on").trim())
        assertTrue(connectivity.contains("Active default network: none") || connectivity.contains("Active default network: null"))
    }
    private fun startApp(resetTask: Boolean = false) {
        val intent = target.packageManager.getLaunchIntentForPackage(target.packageName)!!
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (resetTask) intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK)
        target.startActivity(intent)
    }
    private fun field(): UiObject2 = device.findObject(By.clazz("android.widget.EditText"))
        ?: throw AssertionError("Brak pola tekstowego")
    private fun scrollToField(): UiObject2 {
        repeat(12) {
            val edit = device.findObject(By.clazz("android.widget.EditText"))
            if (edit != null && edit.visibleBounds.height() > 0) return edit
            device.swipe(device.displayWidth / 2, device.displayHeight * 4 / 5, device.displayWidth / 2, device.displayHeight / 3, 30)
        }
        checkpoint("missing-field-${testName.methodName}")
        throw AssertionError("Brak widocznego pola tekstowego")
    }
    private fun checkpoint(name: String) {
        device.dumpWindowHierarchy(File(proofDir, "$name.xml"))
        device.takeScreenshot(File(proofDir, "$name.png"))
    }
    private fun saveReport(name: String, result: JSONObject) {
        result.put("name", name)
        File(proofDir, "$name.json").writeText(result.toString(2))
    }
    private fun freshChat() {
        click("Nowa rozmowa")
        waitFor("Wyślij wiadomość")
    }
    private fun selectLocalProvider() {
        waitFor("Nowa rozmowa")
        if (containing("Demo") != null) {
            click("Demo", contains = true)
            scrollTo("MiniCPM • offline w telefonie")
            click("MiniCPM • offline w telefonie", contains = true)
        }
    }
    private fun send(prompt: String) {
        waitFor("MiniCPM OFFLINE • obliczenia w tym telefonie • bez API")
        enterText(prompt)
        click("Wyślij wiadomość")
        click("Uruchom offline")
    }
    private fun enterText(value: String) {
        field().click()
        SystemClock.sleep(600)
        field().text = value
        SystemClock.sleep(600)
        checkpoint("typed-${testName.methodName}")
    }
    private fun hideKeyboard() {
        if ((device.findObjects(By.pkg("com.google.android.inputmethod.latin")) +
                    device.findObjects(By.pkg("com.android.inputmethod.latin"))).any(::visible)) {
            device.pressBack()
            SystemClock.sleep(500)
        }
    }

    @Test fun a_importSafAndRealChatOffline() {
        startApp(resetTask = true)
        // Pierwszy start ma modalny onboarding; przy ponownym przebiegu nie wraca.
        val end = SystemClock.elapsedRealtime() + 45000
        while (find("Zacznij bez konta") == null && containing("Ustawienia") == null && SystemClock.elapsedRealtime() < end) SystemClock.sleep(250)
        find("Zacznij bez konta")?.click()
        click("Ustawienia", contains = true)
        click("Dostawcy AI", contains = true)
        click("MiniCPM offline w telefonie", contains = true)
        checkpoint("models-before-import")
        // Flutter udostępnia labelText jako wskazówkę pola, nie osobny tekst.
        scrollToField()
        enterText(expectedHash)
        scrollTo("Importuj plik GGUF")
        click("Importuj plik GGUF")
        // Systemowy selektor DocumentsUI, bez wstrzykiwania wyniku Activity.
        // Powrót selektora może pokazać ostatni katalog albo Recents. Otwieramy
        // fizyczny katalog, niezależnie od indeksowania MIME w MediaStore.
        repeat(8) {
            if (find("MiniCPM5-1B-Q4_K_M.gguf") != null) return@repeat
            when {
                find("Open from") != null -> {
                    SystemClock.sleep(400)
                    device.findObjects(By.res("android:id/title").text("sdk_gphone_x86_64"))
                        .firstOrNull(::visible)?.click()
                }
                find("Download") != null -> click("Download")
                else -> click("Show roots", contains = true)
            }
            SystemClock.sleep(500)
        }
        click("MiniCPM5-1B-Q4_K_M.gguf")
        waitFor("Model zapisany w telefonie", 120000, contains = true)
        val imported = scrollTo("Wybrany do czatu")
        assertNotNull(imported)
        val store = LocalModelStore(File(target.filesDir, "local_models"))
        val actual = store.get(expectedHash)
        assertEquals(688065920L, actual.bytes)
        assertEquals("minicpm5_1b", actual.profile)
        assertEquals("5aeac37a35b44fde4bdffaec9159f2fcb253b622", NativeLlama.version())
        device.takeScreenshot(File(proofDir, "imported.png"))
        device.pressBack(); device.pressBack()
        click("Czat", contains = true)
        selectLocalProvider()
        freshChat()
        val began = SystemClock.elapsedRealtime()
        send("Reply with only the single word: OK")
        val completed = waitFor("Ukończono • 0 USD za API", 210000, contains = true)
        val usage = completed.text ?: completed.contentDescription ?: ""
        assertTrue("Model rzeczywiście wyemitował tokeny: $usage", Regex("wyjście [1-9][0-9]* tokenów").containsMatchIn(usage))
        // Sam prompt też zawiera OK; sprawdzamy osobny węzeł odpowiedzi.
        assertNotNull("Odpowiedź prawdziwego modelu", find("OK") ?: find("OK."))
        device.takeScreenshot(File(proofDir, "offline-chat.png"))
        device.dumpWindowHierarchy(File(proofDir, "offline-chat.xml"))
        saveReport("saf-offline-chat", JSONObject().put("modelSha256", actual.id).put("bytes", actual.bytes).put("elapsedMs", SystemClock.elapsedRealtime() - began).put("engineCommit", NativeLlama.version()).put("usageLabel", usage).put("fixtureOutput", "OK").put("offline", true))
    }

    @Test fun b_realJniStopsAfterFirstToken() {
        val store = LocalModelStore(File(target.filesDir, "local_models"))
        val model = store.get(expectedHash)
        val token = 90001L
        val text = StringBuilder()
        var firstAt = 0L
        NativeLlama.prepare(token)
        val began = SystemClock.elapsedRealtime()
        val result = JSONObject(NativeLlama.generate(token, store.modelFile(model.id).absolutePath, model.profile,
            "[{\"role\":\"user\",\"content\":\"Write a long story about a forest, at least 300 words.\"}]".toByteArray(Charsets.UTF_8), 1024, 128, object : TokenSink {
                override fun onBytes(bytes: ByteArray) {
                    text.append(String(bytes, Charsets.UTF_8))
                    if (firstAt == 0L && text.isNotBlank()) { firstAt = SystemClock.elapsedRealtime(); NativeLlama.cancel(token) }
                }
            }))
        assertFalse(result.toString(), result.has("error"))
        assertTrue("Odebrano token przed anulowaniem", firstAt > 0)
        assertEquals("cancelled", result.getString("finish_reason"))
        assertTrue(result.getInt("output_tokens") > 0)
        val stopMs = SystemClock.elapsedRealtime() - firstAt
        assertTrue("Zatrzymanie po tokenie trwało $stopMs ms", stopMs < 5000)
        saveReport("jni-stream-stop", result.put("elapsedMs", SystemClock.elapsedRealtime() - began).put("stopLatencyMs", stopMs).put("fixtureOutput", text.toString()))
    }

    @Test fun c_uiStopThenNextResponse() {
        startApp(resetTask = true)
        selectLocalProvider()
        freshChat()
        send("Write a long story about a forest, at least 300 words.")
        click("Anuluj generowanie")
        waitFor("Anulowano • 0 USD za API", 30000, contains = true)
        device.takeScreenshot(File(proofDir, "stopped.png"))
        freshChat()
        send("Reply with only the single word: OK")
        val completed = waitFor("Ukończono • 0 USD za API", 210000, contains = true)
        val usage = completed.text ?: completed.contentDescription ?: ""
        assertTrue(Regex("wyjście [1-9][0-9]* tokenów").containsMatchIn(usage))
        assertNotNull(find("OK") ?: find("OK."))
        checkpoint("recovered")
        saveReport("ui-stop-recovery", JSONObject().put("cancelled", true).put("nextGenerationCompleted", true).put("usageLabel", usage))
    }

    @Test fun d_backgroundStopsGeneration() {
        startApp(resetTask = true)
        selectLocalProvider()
        freshChat()
        send("Write a long story about a forest, at least 300 words.")
        waitFor("Anuluj generowanie")
        device.pressHome()
        SystemClock.sleep(1500)
        startApp()
        waitFor("Nowa rozmowa")
        // Powrót do aktywnego edytora może ponownie otworzyć IME i zasłonić kartę.
        SystemClock.sleep(800)
        hideKeyboard()
        waitFor("Anulowano • 0 USD za API", 30000, contains = true)
        device.takeScreenshot(File(proofDir, "background-cancelled.png"))
        saveReport("background-stop", JSONObject().put("cancelledAfterHome", true))
    }
}
