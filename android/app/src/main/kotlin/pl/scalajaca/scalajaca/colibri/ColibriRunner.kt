package pl.scalajaca.scalajaca.colibri

import android.content.*
import android.os.*
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Jeden proces i świeży KV na odpowiedź: brak pamięci ukrytej między rolami. */
class ColibriRunner(private val context: Context) : AutoCloseable {
    private val main = Handler(Looper.getMainLooper())
    private val cancelled = AtomicBoolean()
    private val ready = CountDownLatch(1)
    private val died = CountDownLatch(1)
    @Volatile private var remote: Messenger? = null
    @Volatile private var pipes: List<ParcelFileDescriptor> = emptyList()
    @Volatile private var bound = false
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            try { binder.linkToDeath({ died.countDown() }, 0) } catch (_: RemoteException) { died.countDown() }
            lastWorkerDeath = died
            remote = Messenger(binder); ready.countDown()
            if (cancelled.get()) stop()
        }
        override fun onServiceDisconnected(name: ComponentName) { remote = null; ready.countDown(); died.countDown() }
        override fun onNullBinding(name: ComponentName) { ready.countDown() }
    }
    fun run(directory: File, prompt: ByteArray, contextTokens: Int, maxTokens: Int,
            onBytes: (ByteArray) -> Unit): ColibriProtocol.Usage {
        check(Looper.myLooper() != Looper.getMainLooper())
        if (lastWorkerDeath?.await(3, TimeUnit.SECONDS) == false) throw ColibriFailure("busy")
        val input = ParcelFileDescriptor.createPipe()
        val output = ParcelFileDescriptor.createPipe()
        pipes = input.toList() + output.toList()
        try {
            main.post {
                if (cancelled.get()) { ready.countDown(); return@post }
                bound = context.bindService(Intent(context, ColibriService::class.java), connection, Context.BIND_AUTO_CREATE)
                if (!bound) ready.countDown()
            }
            if (!ready.await(15, TimeUnit.SECONDS)) throw ColibriFailure("timeout")
            if (cancelled.get()) throw ColibriFailure("cancelled")
            val target = remote ?: throw ColibriFailure("model_load")
            val bundle = Bundle().apply {
                putString("directory", directory.canonicalPath)
                putInt("context", contextTokens)
                putParcelable("input", input[0]); putParcelable("output", output[1])
            }
            target.send(Message.obtain(null, ColibriService.RUN).apply { data = bundle })
            input[0].close(); output[1].close()
            return ParcelFileDescriptor.AutoCloseInputStream(output[0]).use { reader ->
                ParcelFileDescriptor.AutoCloseOutputStream(input[1]).use { writer ->
                    ColibriProtocol.generate(reader, writer, prompt, maxTokens) {
                        if (cancelled.get()) throw ColibriFailure("cancelled")
                        onBytes(it)
                    }
                }
            }
        } catch (e: Exception) {
            if (cancelled.get()) throw ColibriFailure("cancelled")
            throw e
        } finally { close() }
    }
    fun stop() {
        cancelled.set(true)
        try { remote?.send(Message.obtain(null, ColibriService.STOP)) } catch (_: Exception) {}
        // Zamknięcie obu końców wybudza także odczyt w czasie ładowania modelu.
        pipes.forEach { try { it.close() } catch (_: Exception) {} }
        main.post {
            if (bound) { bound = false; try { context.unbindService(connection) } catch (_: Exception) {} }
        }
    }
    override fun close() {
        stop()
        // Następna generacja nie może przywiązać się do kończącego procesu.
        if (Looper.myLooper() != Looper.getMainLooper() && remote != null) died.await(3, TimeUnit.SECONDS)
    }
    companion object { @Volatile private var lastWorkerDeath: CountDownLatch? = null }
}
