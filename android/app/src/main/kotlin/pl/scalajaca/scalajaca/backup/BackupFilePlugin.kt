package pl.scalajaca.scalajaca.backup

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/** Anulowanie i sukces są rozstrzygane atomowo, również przy ostatnim bloku. */
class BackupCompletionGate {
    private val state = AtomicInteger(0) // 0=trwa, 1=anulowano, 2=ukończono
    val cancelled: Boolean get() = state.get() == 1
    fun cancel(): Boolean = state.compareAndSet(0, 1)
    fun complete(): Boolean = state.compareAndSet(0, 2)
}

/** Twarde granice transportu szyfrotekstu; bez przetwarzania haseł i treści jawnej. */
object BackupFilePolicy {
    const val MAX_ARCHIVE = 2147483648L
    const val MAX_WRITE = 262144
    const val MAX_READ = 65536
    const val DIRECTORY = "scalajaca-backup-ciphertext-v1"
    private val stage = Regex("[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\\.stage")
    fun stageName(value: String): Boolean = stage.matches(value)
    fun growth(current: Long, bytes: Int): Boolean = current in 0..MAX_ARCHIVE &&
        bytes in 0..MAX_WRITE && current <= MAX_ARCHIVE - bytes
    fun readSize(bytes: Int): Boolean = bytes in 1..MAX_READ
    fun filename(value: String): Boolean = value.length in 13..120 &&
        value.endsWith(".scalabackup", true) && !value.startsWith('.') &&
        value.none { it == '/' || it == '\\' || it == ':' || it in "*?<>|\"" || it.code < 32 || it.code == 127 }
}

/**
 * Strumieniowy SAF. Jedyny plik pośredni zawiera wyłącznie otrzymany szyfrotekst.
 * Metody nie przyjmują ścieżek ani URI z Darta i nigdy nie logują danych.
 */
class BackupFilePlugin(private val activity: Activity, messenger: BinaryMessenger) : AutoCloseable {
    companion object {
        const val PICK_SAVE = 8130
        const val PICK_OPEN = 8131
        // Chroni aktywne stage także podczas odtwarzania Activity w tym samym procesie.
        private val activeStages = ConcurrentHashMap.newKeySet<String>()
    }
    private val channel = MethodChannel(messenger, "pl.scalajaca/backup_files")
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private val destroyed = AtomicBoolean(false)
    private val handles = ConcurrentHashMap<String, Handle>()
    private val replies = ConcurrentHashMap.newKeySet<Reply>()
    @Volatile private var pending: Pending? = null
    @Volatile private var activeSignal: CancellationSignal? = null
    @Volatile private var activeHandle: String? = null
    private val cache = activity.cacheDir.canonicalFile
    private val directory = File(cache, BackupFilePolicy.DIRECTORY)

    private class Limit : IllegalArgumentException()
    private class Cancelled : IllegalStateException()
    private sealed class Handle(val id: String) {
        val completion = BackupCompletionGate()
        val cleanupQueued = AtomicBoolean(false)
        var bytes = 0L
        abstract fun dispose()
    }
    private class Writer(id: String, val file: File, var stream: FileOutputStream?) : Handle(id) {
        override fun dispose() { runCatching { stream?.close() }; stream = null }
    }
    private class Reader(id: String, val stream: InputStream) : Handle(id) {
        var eof = false
        override fun dispose() { runCatching { stream.close() } }
    }
    private data class Pending(val reply: Reply, val writer: Writer? = null)
    private inner class Reply(private val result: MethodChannel.Result) {
        private val completed = AtomicBoolean(false)
        init { replies.add(this) }
        fun success(value: Any?) {
            if (!completed.compareAndSet(false, true)) return
            replies.remove(this)
            main.post { runCatching { result.success(value) } }
        }
        fun error(code: String) {
            if (!completed.compareAndSet(false, true)) return
            replies.remove(this)
            val message = when (code) {
                "busy" -> "Poczekaj na zakończenie operacji na kopii zapasowej."
                "limit" -> "Przekroczono rozmiar bloku lub limit kopii 2 GiB."
                "cancelled" -> "Operację na kopii zapasowej anulowano."
                else -> "Nie można odczytać lub zapisać pliku kopii zapasowej."
            }
            main.post { runCatching { result.error(code, message, null) } }
        }
    }

    init { channel.setMethodCallHandler(::call) }

    private fun checkActive(handle: Handle? = null) {
        if (destroyed.get() || handle?.completion?.cancelled == true) throw Cancelled()
    }

    private fun call(call: MethodCall, result: MethodChannel.Result) {
        val reply = Reply(result)
        if (destroyed.get()) { reply.error("cancelled"); return }
        if (call.method == "close") {
            val id = (call.arguments as? Map<*, *>)?.get("id") as? String ?: ""
            val handle = handles[id]
            if (handle == null) { reply.success(null); return }
            val cancelled = handle.completion.cancel()
            if (pending?.writer === handle) {
                // Picker i tak kończy się przez activityResult; nie otwieramy drugiego w tle.
                @Suppress("DEPRECATION")
                runCatching { activity.finishActivity(PICK_SAVE) }
            }
            if (cancelled && activeHandle == id) activeSignal?.cancel()
            if (!handle.cleanupQueued.compareAndSet(false, true)) { reply.success(null); return }
            worker.execute { cleanup(handle); reply.success(null) }
            return
        }
        if (call.method !in setOf("create", "write", "save", "open", "read")) {
            replies.remove(reply)
            result.notImplemented()
            return
        }
        if (!busy.compareAndSet(false, true)) { reply.error("busy"); return }
        worker.execute {
            var picker = false
            var value: Any? = null
            var failure: String? = null
            val id = (call.arguments as? Map<*, *>)?.get("id") as? String ?: ""
            try {
                checkActive()
                when (call.method) {
                    "create" -> {
                        ensureDirectoryAndRemoveAbandoned()
                        require(handles.size < 4)
                        val token = UUID.randomUUID().toString()
                        val file = File(directory, "$token.stage")
                        validateStage(file)
                        check(file.createNewFile())
                        activeStages.add(file.absolutePath)
                        try {
                            val handle = Writer(token, file, FileOutputStream(file, false))
                            handles[token] = handle
                            checkActive(handle)
                            value = token
                        } catch (error: Exception) {
                            handles.remove(token)?.dispose()
                            deleteStage(file)
                            throw error
                        }
                    }
                    "write" -> {
                        val handle = handles[id] as? Writer ?: error("handle")
                        checkActive(handle)
                        val bytes = call.argument<ByteArray>("bytes") ?: error("bytes")
                        if (!BackupFilePolicy.growth(handle.bytes, bytes.size)) throw Limit()
                        val stream = handle.stream ?: error("sealed")
                        stream.write(bytes)
                        handle.bytes += bytes.size
                        checkActive(handle)
                    }
                    "save" -> {
                        val handle = handles[id] as? Writer ?: error("handle")
                        checkActive(handle)
                        val name = call.argument<String>("filename") ?: ""
                        require(BackupFilePolicy.filename(name))
                        val stream = handle.stream ?: error("sealed")
                        stream.flush()
                        stream.fd.sync()
                        stream.close()
                        handle.stream = null
                        checkActive(handle)
                        pending = Pending(reply, handle)
                        picker = true
                        main.post { launchSave(name, reply, handle) }
                    }
                    "open" -> {
                        ensureDirectoryAndRemoveAbandoned()
                        require(handles.size < 4)
                        pending = Pending(reply)
                        picker = true
                        main.post { launchOpen(reply) }
                    }
                    "read" -> {
                        val handle = handles[id] as? Reader ?: error("handle")
                        val size = call.argument<Int>("maxBytes") ?: BackupFilePolicy.MAX_READ
                        if (!BackupFilePolicy.readSize(size)) throw Limit()
                        checkActive(handle)
                        if (handle.eof) value = ByteArray(0) else {
                            val remaining = BackupFilePolicy.MAX_ARCHIVE - handle.bytes
                            if (remaining == 0L) {
                                if (handle.stream.read() >= 0) throw Limit()
                                handle.eof = true
                                handle.dispose()
                                value = ByteArray(0)
                            } else {
                                val buffer = ByteArray(minOf(size.toLong(), remaining).toInt())
                                var count = 0
                                var attempts = 0
                                while (count == 0) {
                                    checkActive(handle)
                                    count = handle.stream.read(buffer)
                                    check(++attempts <= 16)
                                }
                                checkActive(handle)
                                if (count < 0) {
                                    handle.eof = true
                                    handle.dispose()
                                    value = ByteArray(0)
                                } else {
                                    handle.bytes += count
                                    value = if (count == buffer.size) buffer else buffer.copyOf(count)
                                }
                            }
                        }
                    }
                }
            } catch (error: Exception) {
                handles[id]?.let(::cleanup)
                failure = code(error)
            } finally {
                if (!picker) {
                    busy.set(false)
                    if (failure != null) reply.error(failure) else reply.success(value)
                }
            }
        }
    }

    private fun launchSave(name: String, reply: Reply, writer: Writer) {
        try {
            checkActive(writer)
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/octet-stream"
                putExtra(Intent.EXTRA_TITLE, name)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, PICK_SAVE)
        } catch (error: Exception) {
            pending = null
            if (destroyed.get()) { reply.error("cancelled"); return }
            worker.execute { cleanup(writer); busy.set(false); reply.error(code(error)) }
        }
    }
    private fun launchOpen(reply: Reply) {
        try {
            checkActive()
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, PICK_OPEN)
        } catch (error: Exception) {
            pending = null
            busy.set(false)
            reply.error(code(error))
        }
    }

    fun activityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_SAVE && requestCode != PICK_OPEN) return false
        val pick = pending ?: return true
        pending = null
        val uri = data?.data
        val returnedFlags = data?.flags ?: 0
        worker.execute {
            var value: Any? = null
            var failure: String? = null
            try {
                checkActive(pick.writer)
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    value = if (pick.writer != null) false else null
                } else {
                    require(uri.scheme == "content")
                    val flags = if (pick.writer != null) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else Intent.FLAG_GRANT_READ_URI_PERMISSION
                    require(returnedFlags and flags == flags)
                    if (pick.writer != null) {
                        copyCiphertext(pick.writer, uri)
                        if (!pick.writer.completion.complete()) throw Cancelled()
                        value = true
                    } else {
                        val signal = CancellationSignal()
                        activeSignal = signal
                        val descriptor = activity.contentResolver.openFileDescriptor(uri, "r", signal) ?: error("input")
                        try {
                            if (descriptor.statSize > BackupFilePolicy.MAX_ARCHIVE) throw Limit()
                            checkActive()
                            val id = UUID.randomUUID().toString()
                            handles[id] = Reader(id, ParcelFileDescriptor.AutoCloseInputStream(descriptor))
                            value = id
                        } catch (error: Exception) { descriptor.close(); throw error }
                    }
                }
            } catch (error: Exception) {
                failure = code(error)
            } finally {
                activeSignal = null
                activeHandle = null
                pick.writer?.let(::cleanup)
                busy.set(false)
                if (failure != null) pick.reply.error(failure) else pick.reply.success(value)
            }
        }
        return true
    }

    private fun copyCiphertext(writer: Writer, uri: Uri) {
        validateStage(writer.file)
        check(writer.file.length() == writer.bytes && writer.bytes <= BackupFilePolicy.MAX_ARCHIVE)
        val signal = CancellationSignal()
        activeHandle = writer.id
        activeSignal = signal
        val descriptor = activity.contentResolver.openFileDescriptor(uri, "wt", signal) ?: error("output")
        descriptor.use {
            ParcelFileDescriptor.AutoCloseOutputStream(it).use { output ->
                FileInputStream(writer.file).use { input ->
                    val buffer = ByteArray(BackupFilePolicy.MAX_READ)
                    var copied = 0L
                    while (true) {
                        checkActive(writer)
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (copied > BackupFilePolicy.MAX_ARCHIVE - count) throw Limit()
                        output.write(buffer, 0, count)
                        copied += count
                    }
                    check(copied == writer.bytes)
                    output.flush()
                }
            }
        }
        checkActive(writer)
    }

    private fun ensureDirectoryAndRemoveAbandoned() {
        check(directory.canonicalFile.parentFile == cache && directory.canonicalFile.name == BackupFilePolicy.DIRECTORY)
        if (!directory.exists()) check(directory.mkdir())
        check(directory.isDirectory && !OsConstants.S_ISLNK(Os.lstat(directory.absolutePath).st_mode))
        // Bez rekursji: wyłącznie dokładnie nazwane stage bez aktywnego właściciela w tym procesie.
        for (file in directory.listFiles() ?: error("cache")) {
            if (!BackupFilePolicy.stageName(file.name) || activeStages.contains(file.absolutePath)) continue
            validateStage(file)
            check(file.delete())
        }
    }
    private fun validateStage(file: File) {
        check(directory.canonicalFile == directory.absoluteFile && directory.canonicalFile.parentFile == cache)
        check(directory.isDirectory && !OsConstants.S_ISLNK(Os.lstat(directory.absolutePath).st_mode))
        check(BackupFilePolicy.stageName(file.name) && file.absoluteFile.parentFile == directory.absoluteFile)
        check(file.canonicalFile.parentFile == directory.canonicalFile && file.canonicalFile.name == file.name)
        if (file.exists()) check(file.isFile && !OsConstants.S_ISLNK(Os.lstat(file.absolutePath).st_mode))
    }
    private fun deleteStage(file: File) {
        try {
            validateStage(file)
            if (file.exists()) check(file.delete())
        } finally { activeStages.remove(file.absolutePath) }
    }
    private fun cleanup(handle: Handle) {
        handle.completion.cancel()
        handle.dispose()
        handles.remove(handle.id, handle)
        if (handle is Writer) runCatching { deleteStage(handle.file) }
    }
    private fun code(error: Exception): String = when (error) {
        is Limit -> "limit"
        is Cancelled -> "cancelled"
        else -> "file_error"
    }

    /** Picker sam wywołuje onStop. Tylko onDestroy zamyka właściciela strumieni. */
    override fun close() {
        if (!destroyed.compareAndSet(false, true)) return
        channel.setMethodCallHandler(null)
        activeSignal?.cancel()
        handles.values.forEach { it.completion.cancel() }
        pending = null
        replies.toList().forEach { it.error("cancelled") }
        worker.execute { handles.values.toList().forEach(::cleanup) }
        worker.shutdown()
    }
}
