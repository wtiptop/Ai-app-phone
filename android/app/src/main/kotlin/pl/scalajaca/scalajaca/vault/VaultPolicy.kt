package pl.scalajaca.scalajaca.vault

/** Reguły niezależne od Androida. Nie normalizujemy niebezpiecznych ścieżek. */
object VaultPolicy {
    const val MAX_BYTES = 1024 * 1024
    const val MAX_DEPTH = 20
    const val MAX_PATH = 1024
    const val EXPORTS = "Scalajaca-Exports"
    const val AUTHORITY = "com.android.externalstorage.documents"

    fun segment(value: String): Boolean = value.isNotEmpty() && value.length <= 255 &&
        value != "." && value != ".." && !value.startsWith(".") &&
        value.none { it == '/' || it == '\\' || it == ':' || it.code < 32 || it.code == 127 }

    fun relative(value: String): Boolean = value.isNotEmpty() && value.length <= MAX_PATH &&
        value.split('/').let { parts -> parts.size <= MAX_DEPTH && parts.all(::segment) } &&
        value.split('/').none { it == EXPORTS || it.equals("Android", true) }

    fun root(value: String): Boolean {
        if (value.length > MAX_PATH || value.count { it == ':' } != 1) return false
        val storage = value.substringBefore(':')
        val path = value.substringAfter(':')
        return storage.matches(Regex("[A-Za-z0-9-]{1,80}")) &&
            path.isNotEmpty() && relative(path)
    }

    fun descendant(rootId: String, id: String): String? {
        if (!root(rootId) || !id.startsWith("$rootId/")) return null
        val relative = id.substring(rootId.length + 1)
        return relative.takeIf(::relative)
    }

    fun markdown(name: String): Boolean = segment(name) &&
        (name.endsWith(".md", true) || name.endsWith(".markdown", true))

    fun exportName(value: String): Boolean = value.length in 1..80 && markdown(value) &&
        value.none { it in "*?<>|\"" }
}
