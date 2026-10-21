package pl.scalajaca.scalajaca.colibri

import android.app.Service
import android.content.Intent
import android.os.*
import android.os.Process

/** Nieeksportowany proces roboczy. Awaria C nie kończy procesu Fluttera.
 * To izolacja awarii, nie sandbox uprawnień: proces ma UID aplikacji. */
class ColibriService : Service() {
    external fun runNative(directory: String, input: Int, output: Int, context: Int): Int
    private var started = false
    private val messenger = Messenger(Handler(Looper.getMainLooper()) { msg ->
        when (msg.what) {
            STOP -> Process.killProcess(Process.myPid())
            RUN -> if (!started) {
                started = true
                val data = msg.data
                data.classLoader = ParcelFileDescriptor::class.java.classLoader
                @Suppress("DEPRECATION")
                val input = data.getParcelable<ParcelFileDescriptor>("input")!!
                @Suppress("DEPRECATION")
                val output = data.getParcelable<ParcelFileDescriptor>("output")!!
                Thread({
                    try {
                        System.loadLibrary("scalajaca_colibri")
                        input.use { i -> output.use { o ->
                            runNative(data.getString("directory")!!, i.fd, o.fd, data.getInt("context"))
                        } }
                    } finally { Process.killProcess(Process.myPid()) }
                }, "colibri-native").start()
            }
        }
        true
    })
    override fun onBind(intent: Intent) = messenger.binder
    override fun onUnbind(intent: Intent): Boolean {
        Process.killProcess(Process.myPid())
        return false
    }
    companion object { const val RUN = 1; const val STOP = 2 }
}
