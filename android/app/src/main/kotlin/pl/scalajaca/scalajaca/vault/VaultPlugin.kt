package pl.scalajaca.scalajaca.vault

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.DocumentsContract as D
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** Lokalny SAF: bez sieci, pluginów Obsidiana i dowolnych URI przekazywanych z Darta. */
class VaultPlugin(private val activity: Activity, messenger: BinaryMessenger) : AutoCloseable {
    companion object { const val PICK = 8120 }
    private val channel = MethodChannel(messenger, "pl.scalajaca/vault")
    private val prefs = activity.getSharedPreferences("vault_handles_v1", Activity.MODE_PRIVATE)
    private val resolver = activity.contentResolver
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private var pending: MethodChannel.Result? = null
    private var pendingWrite = false
    @Volatile private var operation: Operation? = null
    private val secret: ByteArray = synchronized(prefs) {
        prefs.getString("key", null)?.let { Base64.decode(it, Base64.NO_WRAP) } ?: ByteArray(32).also {
            SecureRandom().nextBytes(it)
            check(prefs.edit().putString("key", Base64.encodeToString(it, Base64.NO_WRAP)).commit())
        }
    }
    private data class Handle(val id: String, val uri: Uri, val root: String, val writable: Boolean) {
        fun wire() = mapOf("id" to id, "writable" to writable)
    }
    private class Operation(val handle: String) {
        val signal = CancellationSignal()
        val end = SystemClock.elapsedRealtime() + 15_000L
        fun check() {
            signal.throwIfCanceled()
            check(SystemClock.elapsedRealtime() < end) { "timeout" }
        }
    }
    private data class Frame(val id: String, var offset: Int = 0)
    private class InvalidCursor : IllegalArgumentException()
    private class Revoked : IllegalStateException()
    private val columns = arrayOf(D.Document.COLUMN_DOCUMENT_ID, D.Document.COLUMN_DISPLAY_NAME,
        D.Document.COLUMN_MIME_TYPE, D.Document.COLUMN_SIZE, D.Document.COLUMN_LAST_MODIFIED,
        D.Document.COLUMN_FLAGS)

    init { channel.setMethodCallHandler(::call) }

    private fun handles(): List<Handle> {
        val data = JSONArray(prefs.getString("handles", "[]"))
        return (0 until data.length()).map { i ->
            val h = data.getJSONObject(i)
            val uri = Uri.parse(h.getString("uri"))
            Handle(h.getString("id"), uri, D.getTreeDocumentId(uri), h.getBoolean("write"))
        }
    }
    private fun save(values: List<Handle>) {
        val data = JSONArray()
        values.forEach { h -> data.put(JSONObject().put("id", h.id).put("uri", h.uri.toString()).put("write", h.writable)) }
        check(prefs.edit().putString("handles", data.toString()).commit())
    }
    private fun get(id: String): Handle {
        val h = handles().firstOrNull { it.id == id } ?: throw Revoked()
        require(h.uri.authority == VaultPolicy.AUTHORITY && VaultPolicy.root(h.root))
        if (!resolver.persistedUriPermissions.any { it.uri == h.uri && it.isReadPermission && (!h.writable || it.isWritePermission) }) throw Revoked()
        return h
    }
    private fun call(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "pick" -> {
                    check(pending == null && !busy.get())
                    // Limit nowych uchwytów sprawdzamy po wyborze: ponowny
                    // odczyt tego samego vaultu może użyć istniejącego ID.
                    pendingWrite = call.argument<Boolean>("writable") == true
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        if (pendingWrite) addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    }
                    pending = result
                    @Suppress("DEPRECATION")
                    activity.startActivityForResult(intent, PICK)
                }
                "status" -> result.success(handles().map { h ->
                    h.wire() + mapOf("available" to resolver.persistedUriPermissions.any {
                        it.uri == h.uri && it.isReadPermission && (!h.writable || it.isWritePermission)
                    })
                })
                "cancel" -> {
                    val id = call.argument<String>("handleId") ?: ""
                    if (operation?.handle == id) operation?.signal?.cancel()
                    result.success(null)
                }
                "disconnect" -> {
                    val h = handles().firstOrNull { it.id == call.argument<String>("handleId") }
                    if (h != null) {
                        if (operation?.handle == h.id) operation?.signal?.cancel()
                        val others = handles().filter { it.id != h.id }
                        save(others)
                        // Inny uchwyt tego samego drzewa może nadal potrzebować odczytu.
                        val shared = others.any { it.uri == h.uri }
                        if (!shared) runCatching { resolver.releasePersistableUriPermission(h.uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or if (h.writable) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else 0) }
                        else if (h.writable && others.none { it.uri == h.uri && it.writable }) runCatching {
                            resolver.releasePersistableUriPermission(h.uri, Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        }
                    }
                    result.success(null)
                }
                "list", "read", "export" -> {
                    if (pending != null || !busy.compareAndSet(false, true)) {
                        result.error("busy", "Poczekaj na zakończenie operacji na pamięci.", null)
                        return
                    }
                    val id = call.argument<String>("handleId") ?: ""
                    val op = Operation(id)
                    operation = op
                    val timeout = Runnable { op.signal.cancel() }
                    main.postDelayed(timeout, 15_000L)
                    worker.execute {
                        try {
                            val h = get(id)
                            val value = when (call.method) {
                                "list" -> listing(h, call.argument("cursor"), call.argument<Int>("limit") ?: 100, op)
                                "read" -> read(h, call.argument<String>("documentId") ?: "", op)
                                else -> export(h, call.argument<String>("filename") ?: "", call.argument<String>("content") ?: "", op)
                            }
                            op.check()
                            main.post { result.success(value) }
                        } catch (error: Exception) {
                            main.post { result.error(if (error is InvalidCursor) "invalid_cursor" else if (error is Revoked) "revoked" else if (error is SecurityException) "permission" else if (op.signal.isCanceled) "cancelled" else "vault_error",
                                if (op.signal.isCanceled) "Operację anulowano lub przekroczono czas. Możesz wznowić skanowanie."
                                else "Operacja niedostępna. Sprawdź uprawnienie, format UTF-8 i limit 1 MiB.", null) }
                        } finally {
                            main.removeCallbacks(timeout)
                            operation = null
                            busy.set(false)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            if (call.method == "pick") pending = null
            result.error("vault_error", "Nie można otworzyć pamięci lokalnej. Wybierz katalog w pamięci telefonu lub na karcie SD.", null)
        }
    }

    fun activityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != PICK) return false
        val result = pending ?: return true
        pending = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) { result.success(null); return true }
        try {
            val uri = data.data!!
            require(uri.scheme == "content" && uri.authority == VaultPolicy.AUTHORITY && D.isTreeUri(uri))
            // Wyłącznie systemowy lokalny provider. Odrzuca chmurę, skróty i obce pluginy.
            @Suppress("DEPRECATION")
            val provider = activity.packageManager.resolveContentProvider(VaultPolicy.AUTHORITY, 0) ?: error("provider")
            check(provider.applicationInfo.flags and (ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0)
            val root = D.getTreeDocumentId(uri)
            require(VaultPolicy.root(root))
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or if (pendingWrite) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else 0
            require(data.flags and flags == flags && data.flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION != 0)
            val current = handles()
            // Eksport ma osobny, tymczasowy uchwyt zapisu, odłączany po operacji.
            // Nie wolno go współdzielić ani podnosić praw uchwytu tylko do odczytu.
            val reusable = if (!pendingWrite) current.firstOrNull { it.uri == uri && !it.writable } else null
            if (reusable == null && current.size >= 8) {
                result.error("vault_limit", "Osiągnięto limit 8 połączeń. Możesz ponownie wybrać już połączony vault tylko do odczytu albo odłączyć nieużywane źródło, zachowując jego dane.", null)
                return true
            }
            resolver.takePersistableUriPermission(uri, flags)
            val h = reusable ?: Handle(UUID.randomUUID().toString(), uri, root, pendingWrite)
            if (reusable == null) save(current + h)
            result.success(h.wire() + mapOf("available" to true))
        } catch (_: Exception) {
            result.error("vault_error", "Wybierz zwykły lokalny katalog vaultu w pamięci telefonu lub na karcie SD. Dostawcy chmurowi i ukryte katalogi są wyłączone.", null)
        }
        return true
    }

    private fun signed(payload: JSONObject): String {
        val bytes = payload.toString().toByteArray(StandardCharsets.UTF_8)
        val mac = Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(secret, "HmacSHA256")) }.doFinal(bytes)
        return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP) + "." +
            Base64.encodeToString(mac, Base64.URL_SAFE or Base64.NO_WRAP)
    }
    private fun verified(value: String, h: Handle, kind: String): JSONObject {
        require(value.length <= 128 * 1024)
        val parts = value.split('.')
        require(parts.size == 2)
        val bytes = Base64.decode(parts[0], Base64.URL_SAFE or Base64.NO_WRAP)
        val mac = Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(secret, "HmacSHA256")) }.doFinal(bytes)
        require(MessageDigest.isEqual(mac, Base64.decode(parts[1], Base64.URL_SAFE or Base64.NO_WRAP)))
        return JSONObject(String(bytes, StandardCharsets.UTF_8)).also {
            require(it.getString("handle") == h.id && it.getString("kind") == kind)
        }
    }
    private fun documentUri(h: Handle, id: String): Uri {
        require(id == h.root || VaultPolicy.descendant(h.root, id) != null)
        return D.buildDocumentUriUsingTree(h.uri, id)
    }
    private fun listing(h: Handle, cursor: String?, limit: Int, op: Operation): Map<String, Any?> {
        require(limit in 1..200)
        val frames = if (cursor == null) mutableListOf(Frame(h.root)) else try {
            val data = verified(cursor, h, "cursor").getJSONArray("frames")
            require(data.length() in 1..VaultPolicy.MAX_DEPTH + 1)
            (0 until data.length()).map { i -> data.getJSONObject(i).let {
                Frame(it.getString("id"), it.getInt("offset")).also { f ->
                    documentUri(h, f.id)
                    require(f.offset in 0..1_000_000)
                }
            } }.toMutableList()
        } catch (_: Exception) { throw InvalidCursor() }
        val out = mutableListOf<Map<String, Any?>>()
        var inspected = 0
        // Metadata cursora Androida jest stronicowana przez CursorWindow; treść plików nie jest tu czytana.
        // Zachowujemy wyłącznie stos głębokości <=20, do200 wyników i1000 rekordów na wywołanie.
        while (frames.isNotEmpty() && out.size < limit && inspected < 1000) {
            op.check()
            val frame = frames.last()
            val children = D.buildChildDocumentsUriUsingTree(h.uri, frame.id)
            var child: Frame? = null
            var exhausted = false
            resolver.query(children, columns, null, null, "${D.Document.COLUMN_DISPLAY_NAME} ASC", op.signal)?.use { rows ->
                if (!rows.moveToPosition(frame.offset)) exhausted = true
                else do {
                    op.check()
                    inspected++
                    frame.offset++
                    require(frame.offset <= 1_000_000)
                    val id = rows.getString(0) ?: ""
                    val name = rows.getString(1) ?: ""
                    val path = VaultPolicy.descendant(h.root, id)
                    val flags = if (rows.isNull(5)) 0 else rows.getInt(5)
                    // Dokładny bezpośredni potomek, bez aliasów w innych poddrzewach i cykli.
                    if (path != null && id == "${frame.id}/$name" && VaultPolicy.segment(name) &&
                        flags and D.Document.FLAG_VIRTUAL_DOCUMENT == 0) {
                        val mime = rows.getString(2) ?: ""
                        if (mime == D.Document.MIME_TYPE_DIR) {
                            if (frames.size <= VaultPolicy.MAX_DEPTH && frames.none { it.id == id }) {
                                child = Frame(id); break
                            }
                        } else if (VaultPolicy.markdown(name)) {
                            val size = if (rows.isNull(3)) -1L else rows.getLong(3)
                            if (size in 0..VaultPolicy.MAX_BYTES.toLong()) {
                                val token = signed(JSONObject().put("handle", h.id).put("kind", "file").put("id", id))
                                out.add(mapOf("id" to token, "path" to path, "bytes" to size,
                                    "modified" to if (rows.isNull(4)) 0L else rows.getLong(4)))
                            }
                        }
                    }
                    if (out.size >= limit || inspected >= 1000) break
                } while (rows.moveToNext().also { if (!it) exhausted = true })
            } ?: error("query")
            if (exhausted) frames.removeAt(frames.lastIndex)
            if (child != null) frames.add(child)
        }
        val next = if (frames.isEmpty()) null else {
            val data = JSONArray()
            frames.forEach { data.put(JSONObject().put("id", it.id).put("offset", it.offset)) }
            signed(JSONObject().put("handle", h.id).put("kind", "cursor").put("frames", data))
        }
        return mapOf("items" to out, "nextCursor" to next)
    }

    private fun read(h: Handle, token: String, op: Operation): String {
        val id = verified(token, h, "file").getString("id")
        require(VaultPolicy.markdown(id.substringAfterLast('/')))
        val uri = documentUri(h, id)
        val bytes = resolver.openFileDescriptor(uri, "r", op.signal)?.use { fd ->
            require(fd.statSize <= VaultPolicy.MAX_BYTES)
            android.os.ParcelFileDescriptor.AutoCloseInputStream(fd).use { stream ->
                val buffer = ByteArray(16 * 1024)
                val out = ByteArrayOutputStream()
                while (true) {
                    op.check()
                    val count = stream.read(buffer)
                    if (count < 0) break
                    require(out.size() + count <= VaultPolicy.MAX_BYTES)
                    out.write(buffer, 0, count)
                }
                out.toByteArray()
            }
        } ?: error("read")
        val decoder = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        return decoder.decode(ByteBuffer.wrap(bytes)).toString().removePrefix("\uFEFF")
    }

    private fun export(h: Handle, filename: String, content: String, op: Operation): String {
        require(h.writable && VaultPolicy.exportName(filename))
        require(content.length <= VaultPolicy.MAX_BYTES)
        val bytes = content.toByteArray(StandardCharsets.UTF_8)
        require(bytes.size <= VaultPolicy.MAX_BYTES)
        op.check()
        val root = documentUri(h, h.root)
        var directory: Uri? = null
        // Eksport jest wyłączony ze skanowania: nie zasila pamięci własnymi kopiami.
        resolver.query(D.buildChildDocumentsUriUsingTree(h.uri, h.root), columns, null, null, null, op.signal)?.use { rows ->
            var count = 0
            while (rows.moveToNext()) {
                op.check(); require(++count <= 1_000_000)
                if (rows.getString(1) == VaultPolicy.EXPORTS) {
                    require(rows.getString(0) == "${h.root}/${VaultPolicy.EXPORTS}" && rows.getString(2) == D.Document.MIME_TYPE_DIR)
                    require(rows.getInt(5) and D.Document.FLAG_VIRTUAL_DOCUMENT == 0)
                    directory = D.buildDocumentUriUsingTree(h.uri, rows.getString(0))
                    break
                }
            }
        } ?: error("query")
        op.check()
        if (directory == null) directory = D.createDocument(resolver, root, D.Document.MIME_TYPE_DIR, VaultPolicy.EXPORTS)
        val dir = directory ?: error("create")
        require(D.getDocumentId(dir) == "${h.root}/${VaultPolicy.EXPORTS}")
        val name = filename.substringBeforeLast('.') + "-" + UUID.randomUUID() + ".md"
        op.check()
        val target = D.createDocument(resolver, dir, "text/markdown", name) ?: error("create")
        require(D.getDocumentId(target) == "${h.root}/${VaultPolicy.EXPORTS}/$name")
        // Tylko świeżo utworzony dokument o losowej nazwie; nigdy oryginał vaultu.
        resolver.openFileDescriptor(target, "w", op.signal)?.use { fd ->
            android.os.ParcelFileDescriptor.AutoCloseOutputStream(fd).use { stream ->
                var offset = 0
                while (offset < bytes.size) {
                    op.check()
                    val count = minOf(16 * 1024, bytes.size - offset)
                    stream.write(bytes, offset, count); offset += count
                }
                stream.flush()
            }
        } ?: error("write")
        return "${VaultPolicy.EXPORTS}/$name"
    }

    fun background() { operation?.signal?.cancel() }
    override fun close() {
        operation?.signal?.cancel()
        pending?.error("cancelled", "Zamknięto wybór katalogu.", null)
        pending = null
        channel.setMethodCallHandler(null)
        worker.shutdownNow()
    }
}
