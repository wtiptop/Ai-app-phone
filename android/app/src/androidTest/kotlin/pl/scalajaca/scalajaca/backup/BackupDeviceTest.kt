package pl.scalajaca.scalajaca.backup

import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.SystemClock
import android.os.Bundle
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Configurator
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TestName
import java.io.File
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.UUID

/**
 * Prawdziwy APK, SQLite, szyfrowanie i DocumentsUI. Wyłącznie własny emulator.
 * Etap b uruchamia host dopiero po jawnym pm clear tej testowej instalacji.
 * Żaden test nie zapisuje hasła, klucza ani treści odszyfrowanej bazy do raportu.
 */
class BackupDeviceTest {
    @get:Rule val testName = TestName()
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val args = InstrumentationRegistry.getArguments()
    private val target = instrumentation.targetContext
    private val device = UiDevice.getInstance(instrumentation)
    private val proof by lazy { File(target.filesDir, "emulator-proof").apply { mkdirs() } }
    private val password = "Scalajaca fictional backup fixture 2026!"
    private val failure = "Operacja nie powiodła się. Dane w aplikacji zachowano."
    private val keys = linkedMapOf(
        "memory_collections" to listOf("id"), "memory_documents" to listOf("id"),
        "memory_versions" to listOf("document_id", "revision"), "memory_chunks" to listOf("id"),
        "analysis_checkpoints" to listOf("id"), "memory_import_jobs" to listOf("collection_id"),
        "rpg_campaigns" to listOf("id"), "rpg_versions" to listOf("campaign_id", "record_id", "revision"),
        "rpg_records" to listOf("campaign_id", "record_id"), "rpg_events" to listOf("campaign_id", "revision"),
        "conversations" to listOf("id"), "messages" to listOf("id"), "chat_scopes" to listOf("conversation_id"),
        "chat_context_receipts" to listOf("message_id"), "notes" to listOf("id"), "tasks" to listOf("id")
    )

    @Before fun emulatorOnlyAndOffline() {
        assertEquals("Test tylko własnego emulatora", "1", shell("getprop ro.kernel.qemu").trim())
        assertEquals("true", args.getString("scalajacaEmulator"))
        val avd = shell("getprop ro.boot.qemu.avd_name").trim().ifEmpty { shell("getprop ro.kernel.qemu.avd_name").trim() }
        assertEquals("Scalajaca_API30", avd)
        Configurator.getInstance().waitForIdleTimeout = 0
        assertOffline()
    }
    @After fun remainsOffline() { assertOffline() }
    private fun shell(command: String) = device.executeShellCommand(command)
    private fun assertOffline() {
        assertEquals("1", shell("settings get global airplane_mode_on").trim())
        val state = shell("dumpsys connectivity")
        assertTrue(state.contains("Active default network: none") || state.contains("Active default network: null"))
    }
    private fun visible(node: UiObject2): Boolean = try {
        node.visibleBounds.let { it.width() > 8 && it.height() > 24 }
    } catch (_: androidx.test.uiautomator.StaleObjectException) { false }
    private fun find(label: String, contains: Boolean = false): UiObject2? {
        val text = if (contains) By.textContains(label) else By.text(label)
        val desc = if (contains) By.descContains(label) else By.desc(label)
        val exact = (device.findObjects(text) + device.findObjects(desc)).filter(::visible)
            .minByOrNull { it.visibleBounds.width() * it.visibleBounds.height() }
        return exact ?: if (!contains) find(label, true) else null
    }
    private fun waitFor(label: String, contains: Boolean = false, timeout: Long = 45000L): UiObject2 {
        val end = SystemClock.elapsedRealtime() + timeout
        do {
            find(label, contains)?.let { return it }
            if ((label.startsWith("Pełna kopia została") ||
                 label.startsWith("Nie można odczytać kopii:") || label == failure) &&
                device.currentPackageName == target.packageName) swipePage(true)
            SystemClock.sleep(200)
        } while (SystemClock.elapsedRealtime() < end)
        checkpoint("failure-${testName.methodName}")
        throw AssertionError("Brak elementu testowego: $label")
    }
    private fun click(label: String, contains: Boolean = false) {
        if (find(label, contains) == null) scrollTo(label, contains)
        waitFor(label, contains)
        SystemClock.sleep(450)
        fun target(): UiObject2 {
            val candidates = device.findObjects(By.clickable(true)).filter {
                visible(it) && it.isEnabled && (it.text.orEmpty().contains(label) || it.contentDescription.orEmpty().contains(label))
            }
            return candidates.minByOrNull { it.visibleBounds.width() * it.visibleBounds.height() } ?: waitFor(label, contains)
        }
        try { target().click() }
        catch (_: androidx.test.uiautomator.StaleObjectException) { target().click() }
        SystemClock.sleep(300)
    }
    private fun scrollTo(label: String, contains: Boolean = false): UiObject2 {
        find(label, contains)?.let { return it }
        repeat(8) {
            swipePage(false)
        }
        repeat(24) {
            find(label, contains)?.let { return it }
            swipePage(true)
        }
        return waitFor(label, contains)
    }
    private fun swipePage(forward: Boolean) {
        // Gest zaczyna się w treści dialogu, a nie w jego nieruchomej stopce.
        val bounds = device.findObjects(By.scrollable(true)).filter(::visible)
            .maxByOrNull { it.visibleBounds.width() * it.visibleBounds.height() }?.visibleBounds
        val x = bounds?.centerX() ?: device.displayWidth / 2
        val top = bounds?.let { it.top + it.height() * 35 / 100 } ?: device.displayHeight * 35 / 100
        val bottom = bounds?.let { it.bottom - it.height() * 35 / 100 } ?: device.displayHeight * 65 / 100
        device.swipe(x, if(forward) bottom else top, x, if(forward) top else bottom, 70)
        SystemClock.sleep(450)
    }
    private fun field(hint: String): UiObject2 {
        device.findObjects(By.clazz("android.widget.EditText").hintContains(hint)).firstOrNull(::visible)?.let { return it }
        repeat(8) {
            swipePage(false)
        }
        repeat(22) {
            device.findObjects(By.clazz("android.widget.EditText").hintContains(hint)).firstOrNull(::visible)?.let { return it }
            swipePage(true)
        }
        throw AssertionError("Brak pola testowego: $hint")
    }
    private fun enter(hint: String, value: String) {
        field(hint)
        fun locate(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            if (node == null) return null
            if (node.className?.toString() == "android.widget.EditText" &&
                node.hintText?.toString().orEmpty().contains(hint) && node.isVisibleToUser) return node
            for (i in 0 until node.childCount) locate(node.getChild(i))?.let { return it }
            return null
        }
        var node = locate(instrumentation.uiAutomation.rootInActiveWindow)
            ?: throw AssertionError("Brak węzła edycji: $hint")
        // RenderEditable udostępnia SET_TEXT dopiero po uzyskaniu fokusu.
        // Wywołujemy tap na dokładnym węźle, bez trafiania w przycięty prostokąt.
        assertTrue("Nie można aktywować pola: $hint", node.performAction(AccessibilityNodeInfo.ACTION_CLICK))
        SystemClock.sleep(600)
        hideKeyboard()
        field(hint)
        node = locate(instrumentation.uiAutomation.rootInActiveWindow)
            ?: throw AssertionError("Zniknęło pole: $hint")
        assertTrue("Pole nie uzyskało fokusu: $hint", node.isFocused)
        val arguments = Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, value) }
        assertTrue("Nie można wpisać wartości: $hint", node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments))
        SystemClock.sleep(600)
        if (!hint.lowercase().contains("hasło")) {
            assertTrue("Nie zapisano wartości pola: $hint", field(hint).text == value)
        }
        hideKeyboard()
    }
    private fun hideKeyboard() {
        if ((device.findObjects(By.pkg("com.google.android.inputmethod.latin")) +
            device.findObjects(By.pkg("com.android.inputmethod.latin"))).any(::visible)) {
            device.pressBack(); SystemClock.sleep(500)
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
            if (find("Zacznij", true) != null) click("Zacznij", true)
            if (find("Ustawienia", true) != null) return
            SystemClock.sleep(250)
        } while (SystemClock.elapsedRealtime() < end)
        waitFor("Ustawienia", contains = true)
    }
    private fun openBackup() {
        click("Ustawienia", true)
        scrollTo("Pełna szyfrowana kopia", true)
        click("Pełna szyfrowana kopia", true)
        scrollTo("Utwórz pełną kopię")
    }
    private fun primaryDocuments() {
        val end = SystemClock.elapsedRealtime() + 30000L
        while (!device.currentPackageName.orEmpty().contains("documentsui") && SystemClock.elapsedRealtime() < end) SystemClock.sleep(200)
        assertTrue("Brak systemowego DocumentsUI", device.currentPackageName.orEmpty().contains("documentsui"))
        val drawer = device.findObject(By.desc("Show roots")) ?: device.findObject(By.desc("Pokaż katalogi główne"))
        if (drawer != null && visible(drawer)) { drawer.click(); SystemClock.sleep(350) }
        val model = shell("getprop ro.product.model").trim()
        click(model)
        click("Documents")
    }
    private fun chooseArchive(filename: String) {
        backupDownloads()
        scrollTo(filename)
        // Ikona "Preview the file <nazwa>" też zawiera nazwę i nie wybiera pliku.
        val title = device.findObjects(By.res("android:id/title").text(filename)).firstOrNull(::visible)
            ?: throw AssertionError("Brak tytułu dokumentu kopii")
        title.click()
        SystemClock.sleep(500)
    }
    private fun backupDownloads() {
        val end = SystemClock.elapsedRealtime() + 120000L
        while (!device.currentPackageName.orEmpty().contains("documentsui") && SystemClock.elapsedRealtime() < end) SystemClock.sleep(200)
        assertTrue("Brak systemowego DocumentsUI", device.currentPackageName.orEmpty().contains("documentsui"))
        val drawer = device.findObject(By.desc("Show roots")) ?: device.findObject(By.desc("Pokaż katalogi główne"))
        if (drawer != null && visible(drawer)) { drawer.click(); SystemClock.sleep(600) }
        val root = device.findObjects(By.res("android:id/title").text("Downloads")).firstOrNull(::visible)
            ?: device.findObjects(By.res("android:id/title").text("Pobrane")).firstOrNull(::visible)
            ?: throw AssertionError("Brak lokalnego katalogu Downloads w selektorze")
        root.click()
        SystemClock.sleep(600)
    }
    private fun fillPassword(value: String, repeat: Boolean = false) {
        enter("Hasło kopii", value)
        if (repeat) enter("Powtórz hasło", value)
    }
    private fun snapshot(): JSONObject {
        val counts = JSONObject(); val identities = JSONObject(); val raw = JSONObject()
        val path = target.getDatabasePath("scalajaca.db").absolutePath
        SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
            // UI i koordynator zakończyły zapis; odczytujemy same metadane/ciphertext.
                for ((table, identityColumns) in keys) {
                    val identity = MessageDigest.getInstance("SHA-256")
                    val ciphertext = MessageDigest.getInstance("SHA-256")
                    var count = 0
                    db.rawQuery("SELECT * FROM $table ORDER BY ${identityColumns.joinToString(",")}", null).use { rows ->
                        while (rows.moveToNext()) {
                            count++
                            for (column in identityColumns) {
                                val bytes = rows.getString(rows.getColumnIndexOrThrow(column)).toByteArray(Charsets.UTF_8)
                                identity.update(ByteBuffer.allocate(4).putInt(bytes.size).array()); identity.update(bytes)
                            }
                            for (column in rows.columnNames.sorted()) {
                                val index = rows.getColumnIndexOrThrow(column)
                                val bytes = if (rows.isNull(index)) byteArrayOf(0) else rows.getString(index).toByteArray(Charsets.UTF_8)
                                ciphertext.update(ByteBuffer.allocate(4).putInt(bytes.size).array()); ciphertext.update(bytes)
                            }
                        }
                    }
                    counts.put(table, count)
                    identities.put(table, identity.digest().joinToString("") { "%02x".format(it.toInt() and 255) })
                    raw.put(table, ciphertext.digest().joinToString("") { "%02x".format(it.toInt() and 255) })
                }
        }
        return JSONObject().put("counts", counts).put("identities", identities).put("ciphertextDigests", raw)
    }
    private fun assertUnchanged(before: JSONObject) {
        val after = snapshot()
        for (section in listOf("counts", "identities", "ciphertextDigests")) {
            for (table in keys.keys) assertEquals("Zmieniono $table/$section", before.getJSONObject(section).get(table), after.getJSONObject(section).get(table))
        }
    }
    private fun assertStageClean() {
        val stage = File(target.cacheDir, BackupFilePolicy.DIRECTORY)
        assertTrue("Pozostał prywatny stage szyfrotekstu", stage.listFiles()?.none { BackupFilePolicy.stageName(it.name) } ?: true)
    }

    private fun createFixtures(suffix: String) {
        click("Pamięć", true)
        click("Notatka")
        enter("Tytuł", "BACKUP_NOTE_$suffix")
        enter("Treść", "Fikcyjna notatka odtwarzania $suffix.")
        click("Zapisz lokalnie")
        click("Obsidian i pamięć projektów", true)
        enter("Nazwa nowego projektu", "BACKUP_PROJECT_$suffix")
        click("Połącz lokalny vault", true)
        primaryDocuments()
        click("ScalajacaBackupVault")
        click("USE THIS FOLDER", true)
        click("ALLOW", true)
        scrollTo("Importuj / wznów")
        click("Importuj / wznów")
        waitFor("Import ukończony", contains = true)
        scrollTo("BackupArchive.md")
        click("BackupArchive.md", true)
        click("Zatwierdź tę wersję")
        enter("Cel analizy", "BACKUP_ANALYSIS_$suffix")
        enter("Ustalenia", "Znaleziono fikcyjny znak RIVERLIGHT.")
        enter("Następny krok", "Porównać wersje przy następnym uruchomieniu.")
        enter("Źródła i wersje", "BackupArchive.md w1")
        scrollTo("Zatwierdź i zapisz punkt wznowienia")
        click("Zatwierdź i zapisz punkt wznowienia")
        device.pressBack(); SystemClock.sleep(400)
        click("Kampanie RPG i lore", true)
        click("Utwórz własną pustą kampanię")
        enter("Nazwa kampanii", "BACKUP_CAMPAIGN_$suffix")
        enter("System i edycja", "TEST_BACKUP_1")
        click("Utwórz pustą")
        scrollTo("Zatwierdź własny wpis")
        click("Zatwierdź własny wpis")
        enter("Tytuł wpisu", "BACKUP_GM_$suffix")
        enter("Treść lub fragment", "Fikcyjny sekret MG $suffix. Nie należy do wiedzy gracza.")
        scrollTo("Zatwierdzam wpis do pamięci MG", true)
        click("Zatwierdzam wpis do pamięci MG", true)
        click("Zapisz zatwierdzony wpis")
        scrollTo("BACKUP_GM_$suffix")
        waitFor("BACKUP_GM_$suffix")
        device.pressBack(); SystemClock.sleep(400)
    }

    @Test fun a_exportSafWrongPasswordAndCollision() {
        val suffix = UUID.randomUUID().toString().substring(0, 8)
        val filename = "Scalajaca-E2E-$suffix.scalabackup"
        assertTrue("Brak syntetycznego vaultu przygotowanego przez hosta", shell("cat /sdcard/Documents/ScalajacaBackupVault/BackupArchive.md").contains("RIVERLIGHT"))
        startApp()
        val reuse = args.getString("scalajacaBackupReuseFixture") == "true"
        val projectFixture = if(reuse) args.getString("scalajacaBackupProjectFixture")!! else suffix
        val campaignFixture = if(reuse) args.getString("scalajacaBackupCampaignFixture")!! else suffix
        require(projectFixture.matches(Regex("[a-f0-9]{8}")) && campaignFixture.matches(Regex("[a-f0-9]{8}")))
        if (!reuse) createFixtures(suffix) else {
            val counts = snapshot().getJSONObject("counts")
            for (table in listOf("notes", "memory_collections", "memory_documents", "memory_versions", "memory_chunks", "analysis_checkpoints", "rpg_campaigns", "rpg_records", "rpg_versions", "rpg_events")) {
                assertTrue("Brak przygotowanych syntetycznych danych: $table", counts.getInt(table) > 0)
            }
        }
        openBackup()
        val before = snapshot()
        fillPassword(password, repeat = true)
        scrollTo("Utwórz pełną kopię")
        click("Utwórz pełną kopię")
        backupDownloads()
        val name = device.findObjects(By.clazz("android.widget.EditText")).firstOrNull(::visible) ?: throw AssertionError("Brak nazwy pliku SAF")
        name.text = filename
        click("SAVE")
        waitFor("Pełna kopia została zapisana.", timeout = 240000L)
        assertStageClean(); assertUnchanged(before)
        checkpoint("backup-saf-export")

        fillPassword("Wrong fictional passphrase 2026!")
        click("Przywróć pełną kopię")
        chooseArchive(filename)
        // Błąd uwierzytelnienia musi wystąpić przed dialogiem zgody i zapisem.
        waitFor("Nie można odczytać kopii: złe hasło lub uszkodzone dane.", timeout = 240000L)
        assertNull("Złe hasło nie może otworzyć zatwierdzenia", find("Przywrócić pełną kopię?"))
        assertUnchanged(before)
        checkpoint("backup-wrong-password")

        fillPassword(password)
        click("Przywróć pełną kopię")
        chooseArchive(filename)
        waitFor("Przywrócić pełną kopię?", timeout = 240000L)
        checkpoint("backup-manifest")
        click("Przywróć")
        waitFor(failure, contains = true, timeout = 240000L)
        assertUnchanged(before); assertStageClean()
        checkpoint("backup-collision-rollback")
        File(proof, "backup-export.json").writeText(JSONObject().put("filename", filename).put("fixture", suffix)
            .put("projectFixture", projectFixture).put("campaignFixture", campaignFixture).put("reusedSyntheticFixture", reuse)
            .put("snapshot", before).put("wrongPasswordNoMutation", true).put("collisionNoMutation", true)
            .put("stageClean", true).put("offline", true).toString(2))
    }

    @Test fun b_restoreAfterAuthorizedEmulatorAppReset() {
        assertEquals("Wymagane świadome wyczyszczenie tylko instalacji testowej", "true", args.getString("scalajacaBackupAfterReset"))
        val suffix = args.getString("scalajacaBackupFixture") ?: error("fixture")
        val filename = args.getString("scalajacaBackupName") ?: error("filename")
        val projectFixture = args.getString("scalajacaBackupProjectFixture") ?: suffix
        val campaignFixture = args.getString("scalajacaBackupCampaignFixture") ?: suffix
        require(projectFixture.matches(Regex("[a-f0-9]{8}")) && campaignFixture.matches(Regex("[a-f0-9]{8}")))
        val secretLabel = "Fikcyjny sekret MG $campaignFixture"
        require(suffix.matches(Regex("[a-f0-9]{8}")) && filename == "Scalajaca-E2E-$suffix.scalabackup")
        startApp()
        openBackup()
        val initial = snapshot()
        for (table in listOf("notes", "memory_collections", "rpg_campaigns", "analysis_checkpoints")) assertEquals("Baza musi być pusta: $table", 0, initial.getJSONObject("counts").getInt(table))
        fillPassword(password)
        click("Przywróć pełną kopię")
        chooseArchive(filename)
        waitFor("Przywrócić pełną kopię?", timeout = 240000L)
        click("Przywróć")
        waitFor("Pełna kopia została przywrócona.", timeout = 240000L)
        val restored = snapshot()
        assertStageClean()
        checkpoint("backup-restored-new-device-key")
        device.pressBack(); SystemClock.sleep(400)
        click("Pamięć", true)
        scrollTo("BACKUP_NOTE_", true)
        waitFor("BACKUP_NOTE_", true)
        // Poprawny odczyt zaszyfrowanych pól po pm clear potwierdza ponowne zaszyfrowanie.
        scrollTo("Obsidian i pamięć projektów", true)
        click("Obsidian i pamięć projektów", true)
        scrollTo("Projekt pamięci", true)
        click("Projekt pamięci", true)
        click("BACKUP_PROJECT_$projectFixture", true)
        scrollTo("BACKUP_ANALYSIS_$projectFixture", true)
        waitFor("BACKUP_ANALYSIS_$projectFixture", true)
        device.pressBack(); SystemClock.sleep(350)
        click("Kampanie RPG i lore", true)
        click("BACKUP_CAMPAIGN_$campaignFixture", true)
        scrollTo("Widok MG z sekretami", true)
        repeat(8) {
            assertNull("Sekret MG nie może być widoczny graczowi", find(secretLabel, true))
            device.swipe(device.displayWidth / 2, device.displayHeight * 4 / 5,
                device.displayWidth / 2, device.displayHeight / 3, 24)
            SystemClock.sleep(250)
        }
        scrollTo("Widok MG z sekretami", true)
        click("Widok MG z sekretami", true)
        scrollTo(secretLabel, true)
        waitFor(secretLabel, true)
        checkpoint("backup-restored-rpg-gm")
        File(proof, "backup-restore.json").writeText(JSONObject().put("filename", filename).put("fixture", suffix)
            .put("snapshot", restored).put("restoredAfterAppDataReset", true).put("encryptedFieldsReadable", true)
            .put("gmSecretHiddenFromPlayer", true).put("offline", true).toString(2))
    }
}
