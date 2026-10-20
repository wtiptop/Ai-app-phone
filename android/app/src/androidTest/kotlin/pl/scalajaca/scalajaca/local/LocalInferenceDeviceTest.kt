package pl.scalajaca.scalajaca.local

import android.content.Intent
import android.os.SystemClock
import android.os.Bundle
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Configurator
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Before
import org.junit.After
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.Rule
import org.junit.rules.TestName
import org.junit.runners.MethodSorters
import java.io.File
import java.util.regex.Pattern

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

    private fun visible(node: UiObject2): Boolean = try {
        node.visibleBounds.let { it.width() > 8 && it.height() > 24 }
    } catch (_: androidx.test.uiautomator.StaleObjectException) { false }
    private fun find(label: String): UiObject2? = (device.findObjects(By.text(label)) + device.findObjects(By.desc(label))).filter(::visible).minByOrNull { it.visibleBounds.width() * it.visibleBounds.height() }
    private fun containing(label: String): UiObject2? = (device.findObjects(By.textContains(label)) + device.findObjects(By.descContains(label))).filter(::visible).minByOrNull { it.visibleBounds.width() * it.visibleBounds.height() }
    private fun waitFor(label: String, timeout: Long = 30000, contains: Boolean = false): UiObject2 {
        val end = SystemClock.elapsedRealtime() + timeout
        do {
            val found = if (contains) containing(label) else find(label)
            if (found != null && visible(found)) return found
            SystemClock.sleep(200)
        } while (SystemClock.elapsedRealtime() < end)
        checkpoint("failure-${testName.methodName}")
        throw AssertionError("Nie znaleziono elementu: $label")
    }
    private fun click(label: String, contains: Boolean = false) {
        // Flutter i UiObject2 inaczej przycinają dolną krawędź viewportu.
        // Aktywujemy dokładną widoczną, klikalną kontrolkę aplikacji jej akcją
        // dostępności; potwierdzenia i asercje następnego stanu pozostają pełne.
        if ((if (contains) containing(label) else find(label)) == null) scrollTo(label)
        SystemClock.sleep(350)
        val appActions = mutableListOf<AccessibilityNodeInfo>()
        fun collect(node: AccessibilityNodeInfo?) {
            if (node == null) return
            val matches = if (contains) node.text?.toString().orEmpty().contains(label) ||
                node.contentDescription?.toString().orEmpty().contains(label)
                else node.text?.toString() == label || node.contentDescription?.toString() == label
            if (node.packageName?.toString() == target.packageName && node.isVisibleToUser &&
                node.isClickable && node.isEnabled && matches) appActions.add(node)
            for (index in 0 until node.childCount) collect(node.getChild(index))
        }
        collect(instrumentation.uiAutomation.rootInActiveWindow)
        val appAction = appActions.minByOrNull {
            val rect = android.graphics.Rect(); it.getBoundsInScreen(rect); rect.width().toLong() * rect.height()
        }
        if (appAction != null && appAction.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
            SystemClock.sleep(400)
            return
        }

        waitFor(label, contains = contains)
        // Węzeł jest widoczny już podczas animacji wysuwanego menu.
        SystemClock.sleep(350)
        try { waitFor(label, contains = contains).click() }
        catch (_: androidx.test.uiautomator.StaleObjectException) {
            SystemClock.sleep(300)
            waitFor(label, contains = contains).click()
        }
        SystemClock.sleep(200)
    }
    private fun scrollTo(label: String): UiObject2 {
        repeat(12) {
            val found = find(label) ?: containing(label)
            if (found != null && visible(found)) return found
            device.swipe(device.displayWidth / 2, device.displayHeight * 4 / 5, device.displayWidth / 2, device.displayHeight / 3, 30)
            SystemClock.sleep(450)
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
                        .filter(::visible).minByOrNull { it.visibleBounds.width() * it.visibleBounds.height() }?.click()
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
            "[{\"role\":\"user\",\"content\":\"Write a long story about a forest, at least 300 words.\"}]".toByteArray(Charsets.UTF_8), 1024, 128, false, object : TokenSink {
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

    /** Kotwiczymy na polu, nie na etykiecie scalonego przodka karty. */
    private fun vaultSearch(query: String) {
        val hint = "Szukaj po słowach w zatwierdzonych źródłach"
        fun edit(label: String) = device.findObjects(By.clazz("android.widget.EditText").hintContains(label))
            .filter { visible(it) && it.visibleBounds.height() >= 80 }.minByOrNull { it.visibleBounds.height() }
        repeat(30) {
            if (edit("Nazwa nowego projektu") != null) return@repeat
            device.swipe(device.displayWidth / 2, device.displayHeight * 35 / 100,
                device.displayWidth / 2, device.displayHeight * 65 / 100, 55)
            SystemClock.sleep(350)
        }
        assertNotNull("Brak górnej kotwicy projektu", edit("Nazwa nowego projektu"))
        repeat(30) {
            if (edit(hint) != null) return@repeat
            device.swipe(device.displayWidth / 2, device.displayHeight * 65 / 100,
                device.displayWidth / 2, device.displayHeight * 35 / 100, 55)
            SystemClock.sleep(350)
        }
        if (edit(hint) == null) {
            checkpoint("vault-query-missing-${testName.methodName}")
            throw AssertionError("Brak właściwego pola wyszukiwania")
        }
        fun locate(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            if (node == null) return null
            if (node.className?.toString() == "android.widget.EditText" &&
                node.hintText?.toString() == hint && node.isVisibleToUser) return node
            for (index in 0 until node.childCount) locate(node.getChild(index))?.let { return it }
            return null
        }
        var node = locate(instrumentation.uiAutomation.rootInActiveWindow)!!
        assertTrue(node.performAction(AccessibilityNodeInfo.ACTION_CLICK))
        SystemClock.sleep(600)
        hideKeyboard()
        node = locate(instrumentation.uiAutomation.rootInActiveWindow)!!
        assertTrue("Pole musi rzeczywiście otrzymać fokus", node.isFocused)
        val arguments = Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, query) }
        assertTrue(node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments))
        SystemClock.sleep(600)
        hideKeyboard()
        assertEquals(query, edit(hint)!!.text)
        checkpoint("vault-query-${testName.methodName}")
        scrollTo("Szukaj w pamięci")
        click("Szukaj w pamięci")
        checkpoint("vault-search-dispatched-${testName.methodName}")
    }

    private fun actualFact(expected: String): String {
        // Całe słowo (ewentualnie kropka), nigdy częściowe trafienie w źródle.
        val literal = Pattern.compile("^\\s*" + Pattern.quote(expected) + "[.]?\\s*$", Pattern.CASE_INSENSITIVE)
        val end = SystemClock.elapsedRealtime() + 15000
        do {
            val node = (device.findObjects(By.text(literal)) + device.findObjects(By.desc(literal)))
                .filter(::visible).minByOrNull { it.visibleBounds.width() * it.visibleBounds.height() }
            if (node != null) return node.text?.takeIf { it.isNotEmpty() } ?: node.contentDescription.orEmpty()
            // Status complete i Markdown mogą dostać osobne klatki semantyki.
            SystemClock.sleep(200)
        } while (SystemClock.elapsedRealtime() < end)
        checkpoint("literal-failure-${testName.methodName}")
        throw AssertionError("Model musi odczytać dokładny fakt $expected (bez wymogu zapisu liter)")
    }

    @Test fun e_localVaultSafSourceAndRealAnswer() {
        // Własne syntetyczne dane. Test nie otwiera prywatnego vaultu.
        val folder = "/sdcard/Documents/ScalajacaTestVault"
        // Fixture przygotowuje skrypt test_android_emulator.ps1 przez adb push.
        // UiAutomation.executeShellCommand nie jest powłoką obsługującą pipe/redirection.
        assertTrue("Brak fixture vaultu; uruchom skrypt przygotowujący test", device.executeShellCommand("cat $folder/Archive.md").contains("LANTERN"))
        assertTrue(device.executeShellCommand("cat $folder/GM_SECRET.md").contains("VAULT_GM_SENTINEL_426"))
        startApp(resetTask = true)
        selectLocalProvider()
        click("Pamięć", contains = true)
        click("Obsidian i pamięć projektów", contains = true)
        click("Połącz lokalny vault", contains = true)
        // Selektor drzewa pamięta ostatni katalog Download, którego Android 11
        // nie pozwala udostępnić jako root. Nawigujemy jawnym breadcrumbem.
        click("sdk_gphone_x86_64")
        click("Documents")
        click("ScalajacaTestVault")
        click("USE THIS FOLDER", contains = true)
        click("ALLOW", contains = true)
        scrollTo("Importuj / wznów")
        click("Importuj / wznów")
        waitFor("Import ukończony", contains = true)
        SystemClock.sleep(600)
        checkpoint("vault-imported")
        scrollTo("Archive.md")
        click("Archive.md", contains = true)
        click("Zatwierdź tę wersję")
        vaultSearch("archive")
        scrollTo("Podgląd wybranych źródeł")
        click("Podgląd wybranych źródeł")
        checkpoint("vault-source-preview")
        assertNull("Sekret nie może trafić do pakietu", containing("VAULT_GM_SENTINEL_426"))
        assertNull("Konfiguracja vaultu jest pomijana", containing("HIDDEN_PLUGIN_SENTINEL_426"))
        click("Użyj w czacie")
        val began = SystemClock.elapsedRealtime()
        send("Copy the archive key from the provided source verbatim. Keep its exact spelling. Reply only with the key.")
        val completed = waitFor("Ukończono • 0 USD za API", 210000, contains = true)
        val usage = completed.text ?: completed.contentDescription ?: ""
        checkpoint("vault-real-answer")
        val actualOutput = actualFact("LANTERN")
        click("Źródła użyte w odpowiedzi")
        waitFor("Zapisany pakiet źródeł")
        assertNotNull(containing("Archive.md"))
        checkpoint("vault-saved-receipt")
        click("Zamknij")
        saveReport("vault-saf-real-answer", JSONObject().put("offline", true).put("fixtureOutput", "LANTERN").put("actualOutput", actualOutput)
            .put("elapsedMs", SystemClock.elapsedRealtime() - began).put("usageLabel", usage)
            .put("source", "Archive.md").put("receiptRetained", true))
    }

    @Test fun f_pagedRecallFindsLateFactOffline() {
        startApp(resetTask = true)
        selectLocalProvider()
        click("Pamięć", contains = true)
        click("Obsidian i pamięć projektów", contains = true)
        vaultSearch("what is the archive")
        scrollTo("Znalezione fragmenty:")
        val first = waitFor("Znalezione fragmenty:", contains = true)
        val summary = first.text ?: first.contentDescription ?: ""
        assertTrue("Fixture musi mieć co najmniej 21 trafień: $summary", Regex("Znalezione fragmenty: (2[1-9]|[3-9][0-9])\\.").containsMatchIn(summary))
        repeat(2) {
            scrollTo("Następne wyniki")
            click("Następne wyniki")
        }
        // Powrót ku początkowi karty, bez odpytywania drugiej UiAutomation.
        repeat(10) {
            if (containing("Strona 3.") != null) return@repeat
            device.swipe(device.displayWidth / 2, device.displayHeight / 3, device.displayWidth / 2, device.displayHeight * 2 / 3, 35)
            SystemClock.sleep(450)
        }
        waitFor("Strona 3.", contains = true)
        checkpoint("memory-page-three")
        vaultSearch("what is the recovery")
        scrollTo("Podgląd wybranych źródeł")
        click("Podgląd wybranych źródeł")
        assertNotNull("Późny fakt musi być w zatwierdzonym pakiecie", containing("COMPASS"))
        assertNull(containing("VAULT_GM_SENTINEL_426"))
        checkpoint("memory-late-fact-preview")
        click("Użyj w czacie")
        val began = SystemClock.elapsedRealtime()
        send("Copy the recovery key from the provided source verbatim. Keep its exact spelling. Reply only with the key.")
        val done = waitFor("Ukończono • 0 USD za API", 210000, contains = true)
        val usage = done.text ?: done.contentDescription ?: ""
        checkpoint("memory-late-fact-answer")
        val actualOutput = actualFact("COMPASS")
        click("Źródła użyte w odpowiedzi")
        waitFor("Zapisany pakiet źródeł")
        assertNotNull(containing("COMPASS"))
        assertNotNull(containing("Archive.md"))
        checkpoint("memory-late-fact-receipt")
        click("Zamknij")
        val repeatedOutputs = JSONArray().put(actualOutput)
        repeat(2) {
            click("Ponów ostatnią odpowiedź")
            click("Uruchom offline")
            // Ta sama zatwierdzona wiadomość, bez starej odpowiedzi w kontekście.
            waitFor("Anuluj generowanie")
            waitFor("Ukończono • 0 USD za API", 210000, contains = true)
            repeatedOutputs.put(actualFact("COMPASS"))
        }
        checkpoint("memory-late-fact-repeated")
        saveReport("paged-memory-real-answer", JSONObject().put("offline", true).put("source", "Archive.md")
            .put("initialResults", summary).put("pageThreeReached", true).put("fixtureOutput", "COMPASS").put("actualOutput", actualOutput)
            .put("repeatedOutputs", repeatedOutputs)
            .put("receiptRetained", true).put("usageLabel", usage).put("elapsedMs", SystemClock.elapsedRealtime() - began))
    }

}
