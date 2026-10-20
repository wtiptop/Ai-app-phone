package pl.scalajaca.scalajaca.rpg

import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.Bundle
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Configurator
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.util.UUID

/**
 * Rzeczywisty APK i SQLite, wyłącznie nowa fikcyjna kampania na własnym AVD.
 * Nie odczytujemy kluczy ani plaintextu innych kampanii, nie czyścimy danych.
 * Test nie korzysta z modeli ani płatnych usług.
 */
class ContinuityDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val args = InstrumentationRegistry.getArguments()
    private val target = instrumentation.targetContext
    private val device = UiDevice.getInstance(instrumentation)
    private val proof by lazy { File(target.filesDir, "emulator-proof").apply { mkdirs() } }
    private var authorizedEmulator = false

    @Before fun ownEmulatorOfflineOnly() {
        assertEquals("Test tylko własnego emulatora", "1", shell("getprop ro.kernel.qemu").trim())
        assertEquals("Wymagane jawne uruchomienie scenariusza", "true", args.getString("scalajacaEmulator"))
        val avd = shell("getprop ro.boot.qemu.avd_name").trim()
            .ifEmpty { shell("getprop ro.kernel.qemu.avd_name").trim() }
        assertEquals("Scalajaca_API30", avd)
        authorizedEmulator = true
        Configurator.getInstance().waitForIdleTimeout = 0
        // Stary raport sukcesu nie może zostać pomylony z nieudanym nowym testem.
        val report = File(proof, "campaign-continuity.json")
        assertTrue("Nie można usunąć poprzedniego raportu testowego", !report.exists() || report.delete())
        File(proof, "campaign-offline-before.txt").writeText(assertOffline())
    }

    @After fun remainsOffline() {
        if (authorizedEmulator) File(proof, "campaign-offline-after.txt").writeText(assertOffline())
    }

    private fun shell(command: String) = device.executeShellCommand(command)
    private fun assertOffline(): String {
        assertEquals("Tryb samolotowy", "1", shell("settings get global airplane_mode_on").trim())
        val state = shell("dumpsys connectivity")
        assertTrue("Emulator ma aktywną sieć", state.contains("Active default network: none") ||
            state.contains("Active default network: null"))
        return state
    }

    private fun visible(node: UiObject2): Boolean = try {
        node.visibleBounds.let { it.width() > 8 && it.height() > 24 }
    } catch (_: androidx.test.uiautomator.StaleObjectException) { false }

    private fun find(label: String, contains: Boolean = false): UiObject2? {
        val nodes = device.findObjects(if (contains) By.textContains(label) else By.text(label)) +
            device.findObjects(if (contains) By.descContains(label) else By.desc(label))
        val found = nodes.filter(::visible).minByOrNull { it.visibleBounds.width() * it.visibleBounds.height() }
        return found ?: if (!contains) find(label, true) else null
    }

    private fun waitFor(label: String, contains: Boolean = false, timeout: Long = 30000L): UiObject2 {
        val end = SystemClock.elapsedRealtime() + timeout
        do {
            find(label, contains)?.let { return it }
            SystemClock.sleep(200)
        } while (SystemClock.elapsedRealtime() < end)
        checkpoint("campaign-continuity-failure")
        throw AssertionError("Brak elementu: $label")
    }

    private fun swipePage(forward: Boolean) {
        // Mały faktyczny viewport, nie scalony węzeł całego ekranu ani EditText.
        val bounds = device.findObjects(By.scrollable(true)).filter {
            visible(it) && it.className != "android.widget.EditText" &&
                it.visibleBounds.height() > 100 && it.visibleBounds.width() > 100
        }.minByOrNull { it.visibleBounds.width() * it.visibleBounds.height() }?.visibleBounds
        val x = bounds?.centerX() ?: device.displayWidth / 2
        val top = bounds?.let { it.top + it.height() * 30 / 100 } ?: device.displayHeight * 30 / 100
        val bottom = bounds?.let { it.bottom - it.height() * 30 / 100 } ?: device.displayHeight * 70 / 100
        device.swipe(x, if (forward) bottom else top, x, if (forward) top else bottom, 65)
        SystemClock.sleep(350)
    }

    private fun scrollTo(label: String, contains: Boolean = false): UiObject2 {
        find(label, contains)?.let { return it }
        repeat(8) { swipePage(false) }
        repeat(24) {
            find(label, contains)?.let { return it }
            swipePage(true)
        }
        return waitFor(label, contains)
    }

    private fun click(label: String, contains: Boolean = false) {
        // Flutter i UiObject2 inaczej przycinają dolną krawędź viewportu.
        // Aktywujemy dokładną widoczną, klikalną kontrolkę aplikacji jej akcją
        // dostępności; potwierdzenia i asercje następnego stanu pozostają pełne.
        if (find(label, contains) == null) scrollTo(label, contains)
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

        if (find(label, contains) == null) scrollTo(label, contains)
        waitFor(label, contains)
        SystemClock.sleep(350)
        fun actionable(): UiObject2 {
            val nodes = device.findObjects(By.clickable(true)).filter {
                visible(it) && it.isEnabled &&
                    (if (contains) it.text.orEmpty().contains(label) || it.contentDescription.orEmpty().contains(label)
                     else it.text == label || it.contentDescription == label)
            }
            return nodes.minByOrNull { it.visibleBounds.width() * it.visibleBounds.height() }
                ?: waitFor(label, contains)
        }
        try { actionable().click() }
        catch (_: androidx.test.uiautomator.StaleObjectException) { actionable().click() }
        SystemClock.sleep(400)
    }

    private fun field(hint: String): UiObject2 {
        fun candidate() = device.findObjects(By.clazz("android.widget.EditText").hintContains(hint))
            .filter(::visible).minByOrNull { it.visibleBounds.width() * it.visibleBounds.height() }
        candidate()?.let { return it }
        repeat(8) { swipePage(false) }
        repeat(24) {
            candidate()?.let { return it }
            swipePage(true)
        }
        checkpoint("campaign-continuity-missing-field")
        throw AssertionError("Brak pola: $hint")
    }

    private fun enter(hint: String, value: String) {
        field(hint)
        fun locate(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            if (node == null) return null
            if (node.className?.toString() == "android.widget.EditText" &&
                node.hintText?.toString() == hint && node.isVisibleToUser) return node
            for (index in 0 until node.childCount) locate(node.getChild(index))?.let { return it }
            return null
        }
        var node = locate(instrumentation.uiAutomation.rootInActiveWindow)
            ?: throw AssertionError("Brak dokładnego węzła edycji: $hint")
        assertTrue("Nie można aktywować pola: $hint", node.performAction(AccessibilityNodeInfo.ACTION_CLICK))
        SystemClock.sleep(600)
        hideKeyboard()
        field(hint)
        node = locate(instrumentation.uiAutomation.rootInActiveWindow)
            ?: throw AssertionError("Zniknęło pole: $hint")
        assertTrue("Pole nie uzyskało fokusu: $hint", node.isFocused)
        val arguments = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, value)
        }
        assertTrue("Nie można wpisać wartości: $hint",
            node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments))
        SystemClock.sleep(600)
        assertEquals("Nie zapisano wartości pola: $hint", value, field(hint).text)
        hideKeyboard()
    }

    private fun hideKeyboard() {
        if ((device.findObjects(By.pkg("com.google.android.inputmethod.latin")) +
            device.findObjects(By.pkg("com.android.inputmethod.latin"))).any(::visible)) {
            device.pressBack()
            SystemClock.sleep(450)
        }
    }

    private fun checkpoint(name: String) {
        device.dumpWindowHierarchy(File(proof, "$name.xml"))
        device.takeScreenshot(File(proof, "$name.png"))
    }

    private fun startApp() {
        val intent = target.packageManager.getLaunchIntentForPackage(target.packageName)!!
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        target.startActivity(intent)
        val end = SystemClock.elapsedRealtime() + 30000L
        do {
            if (find("Zacznij bez konta") != null) click("Zacznij bez konta")
            if (find("Pamięć", true) != null) return
            SystemClock.sleep(250)
        } while (SystemClock.elapsedRealtime() < end)
        waitFor("Pamięć", contains = true)
    }

    private fun <T> readDb(action: (SQLiteDatabase) -> T): T = SQLiteDatabase.openDatabase(
        target.getDatabasePath("scalajaca.db").absolutePath, null, SQLiteDatabase.OPEN_READONLY).use(action)

    private fun lastCampaignRow(): Long = readDb { db ->
        db.rawQuery("SELECT COALESCE(MAX(rowid),0) FROM rpg_campaigns", null).use { rows ->
            assertTrue(rows.moveToFirst()); rows.getLong(0)
        }
    }

    private fun createdCampaign(after: Long): String = readDb { db ->
        db.rawQuery("SELECT id,revision,owner_id FROM rpg_campaigns WHERE rowid>? ORDER BY rowid LIMIT 2",
            arrayOf(after.toString())).use { rows ->
            assertEquals("Powinna powstać wyłącznie jedna własna kampania", 1, rows.count)
            assertTrue(rows.moveToFirst())
            assertEquals(0, rows.getInt(1)); assertEquals("local-owner", rows.getString(2))
            rows.getString(0)
        }
    }

    private fun campaignRevision(id: String): Int = readDb { db ->
        db.rawQuery("SELECT revision FROM rpg_campaigns WHERE id=?", arrayOf(id)).use { rows ->
            assertTrue(rows.moveToFirst()); rows.getInt(0)
        }
    }

    private fun checkpointCipherDigests(id: String, through: Int): Map<Int, String> = readDb { db ->
        val result = linkedMapOf<Int, String>()
        db.rawQuery("SELECT revision,payload FROM rpg_versions WHERE campaign_id=? AND record_id='active-session' AND revision<=? ORDER BY revision",
            arrayOf(id, through.toString())).use { rows ->
            while (rows.moveToNext()) result[rows.getInt(0)] = MessageDigest.getInstance("SHA-256")
                .digest(rows.getString(1).toByteArray(Charsets.UTF_8))
                .joinToString("") { "%02x".format(it.toInt() and 255) }
        }
        result
    }

    private fun assertOwnMetadata(id: String) = readDb { db ->
        db.rawQuery("SELECT revision,kind FROM rpg_events WHERE campaign_id=? ORDER BY revision", arrayOf(id)).use { rows ->
            assertEquals(3, rows.count)
            for (revision in 1..3) {
                assertTrue(rows.moveToNext()); assertEquals(revision, rows.getInt(0))
                assertEquals("checkpointSaved", rows.getString(1))
            }
        }
        db.rawQuery("SELECT revision,kind,visibility,approved FROM rpg_versions WHERE campaign_id=? AND record_id='active-session' ORDER BY revision",
            arrayOf(id)).use { rows ->
            assertEquals(3, rows.count)
            for (revision in 1..3) {
                assertTrue(rows.moveToNext()); assertEquals(revision, rows.getInt(0))
                assertEquals("sessionCheckpoint", rows.getString(1)); assertEquals("gmSecret", rows.getString(2))
                assertEquals(1, rows.getInt(3))
            }
        }
        db.rawQuery("SELECT COUNT(*) FROM rpg_terms WHERE campaign_id=?", arrayOf(id)).use { rows ->
            assertTrue(rows.moveToFirst()); assertEquals("Sekrety nie mogą trafić do indeksu", 0, rows.getInt(0))
        }
    }

    private fun savePoint(values: Map<String, String>) {
        click("Stan sesji · zapisz lub wróć")
        waitFor("Trwały stan sesji · tylko MG")
        for ((hint, value) in values) enter(hint, value)
        click("Zatwierdź zapis sesji")
        scrollTo("Historia sesji MG")
    }

    @Test fun historicalCheckpointResumeAndPlayerIsolation() {
        val fixture = UUID.randomUUID().toString()
        val name = "CONTINUITY_$fixture"
        val edition = "TEST_CONTINUITY_1"
        val old = linkedMapOf("Cel sesji" to "CP1_GOAL_$fixture", "Bieżąca scena" to "CP1_SCENE_$fixture",
            "Otwarte wątki" to "CP1_THREAD_$fixture", "Drużyna" to "CP1_PARTY_$fixture", "Zegar świata" to "CP1_CLOCK_$fixture")
        val latest = linkedMapOf("Cel sesji" to "CP2_GOAL_$fixture", "Bieżąca scena" to "CP2_SCENE_$fixture",
            "Otwarte wątki" to "CP2_THREAD_$fixture", "Drużyna" to "CP2_PARTY_$fixture", "Zegar świata" to "CP2_CLOCK_$fixture")
        startApp()
        click("Pamięć", true)
        click("Kampanie RPG i lore", true)
        val before = lastCampaignRow()
        click("Utwórz własną pustą kampanię")
        enter("Nazwa kampanii", name)
        enter("System i edycja", edition)
        click("Utwórz pustą")
        scrollTo("Widok MG z sekretami", contains = true)
        val campaign = createdCampaign(before)
        savePoint(old)
        assertEquals(1, campaignRevision(campaign))
        savePoint(latest)
        assertEquals(2, campaignRevision(campaign))
        val immutableBefore = checkpointCipherDigests(campaign, 2)
        assertEquals(setOf(1, 2), immutableBefore.keys)

        click("Historia sesji MG")
        waitFor("Rewizja 2 · bieżący punkt", contains = true)
        scrollTo("Rewizja 1", contains = true)
        checkpoint("campaign-history-two-sessions")
        click("Rewizja 1", contains = true)
        waitFor("Archiwalna notatka nie jest aktualnym kanonem", contains = true)
        scrollTo("Cel: ${old.getValue("Cel sesji")}", contains = true)
        waitFor("Cel: ${old.getValue("Cel sesji")}", contains = true)
        checkpoint("campaign-history-preview")
        click("Wybierz punkt do wznowienia")
        waitFor("Wznowić punkt sesji z r1?")
        assertEquals("Podgląd i wybór nie mogą jeszcze zmienić stanu", 2, campaignRevision(campaign))
        click("Wznów jako nową rewizję")
        scrollTo("$edition · rewizja 3", contains = true)
        assertEquals(3, campaignRevision(campaign))
        assertEquals("Wznowienie nie zmienia historycznych szyfrogramów", immutableBefore,
            checkpointCipherDigests(campaign, 2))
        assertOwnMetadata(campaign)

        click("Stan sesji · zapisz lub wróć")
        waitFor("Trwały stan sesji · tylko MG")
        for ((hint, value) in old) assertEquals("Wznowione pole: $hint", value, field(hint).text)
        checkpoint("campaign-resumed-checkpoint-fields")
        click("Zamknij")
        scrollTo("Widok MG z sekretami", contains = true)
        click("Widok MG z sekretami", contains = true)
        repeat(14) {
            assertNull("Gracz nie otrzymuje historii sesji MG", find("Historia sesji MG"))
            assertNull("Gracz nie otrzymuje edycji checkpointu MG", find("Stan sesji · zapisz lub wróć"))
            for (value in old.values + latest.values) assertNull("Sekret checkpointu w widoku gracza", find(value, true))
            swipePage(true)
        }
        scrollTo("Brak wpisów w wybranym widoku.")
        waitFor("Brak wpisów w wybranym widoku.")
        checkpoint("campaign-player-isolation")
        val after = assertOffline()
        File(proof, "campaign-offline-after.txt").writeText(after)
        File(proof, "campaign-continuity.json").writeText(JSONObject()
            .put("fixture", fixture).put("campaignId", campaign)
            .put("initialHistoryRevisions", JSONArray(listOf(1, 2)))
            .put("resumedRevision", 3).put("oldCiphertextPreserved", true)
            .put("resumedFieldsVerifiedViaUi", true).put("gmCheckpointIndexed", false)
            .put("playerNoHistoryOrCheckpoint", true).put("offlineBefore", true).put("offlineAfter", true)
            .put("api", shell("getprop ro.build.version.sdk").trim())
            .put("abi", shell("getprop ro.product.cpu.abi").trim()).toString(2))
    }
}
