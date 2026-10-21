package pl.scalajaca.scalajaca.local

import androidx.test.platform.app.InstrumentationRegistry

/** Tylko dwa przypięte publiczne pliki; parametr runnera nie jest ścieżką. */
internal data class OfflineModelFixture(
    val sha256: String, val filename: String, val bytes: Long, val profile: String
) {
    companion object {
        fun selected(): OfflineModelFixture = when (
            InstrumentationRegistry.getArguments().getString("modelSize", "1b")
        ) {
            "1b" -> OfflineModelFixture(
                "81b64d05a23b17b34c475f42b3e72fbde62d4b92cc34541f7a8031d0752deafa",
                "MiniCPM5-1B-Q4_K_M.gguf", 688065920L, "minicpm5_1b")
            "2b" -> OfflineModelFixture(
                "ec2d5801640099e97d8d7e8003ad4d81f336e757811f03a26173dddf386602fd",
                "MiniCPM5-2B-Q4_K_M.gguf", 1561318368L, "minicpm5_2b")
            else -> throw IllegalArgumentException("Nieznany testowy profil modelu")
        }
    }
}
