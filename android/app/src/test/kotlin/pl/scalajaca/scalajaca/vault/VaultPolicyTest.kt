package pl.scalajaca.scalajaca.vault

import org.junit.Assert.*
import org.junit.Test

class VaultPolicyTest {
    @Test fun acceptsLocalVaultAndMarkdown() {
        assertTrue(VaultPolicy.root("primary:Obsidian/Moja kampania"))
        assertTrue(VaultPolicy.root("ABCD-1234:Vault"))
        assertEquals("Lore/Królestwo.md", VaultPolicy.descendant("primary:Vault", "primary:Vault/Lore/Królestwo.md"))
        assertTrue(VaultPolicy.markdown("NOTATKA.MD"))
        assertTrue(VaultPolicy.markdown("Sesja.markdown"))
    }
    @Test fun rejectsTraversalRatherThanNormalizing() {
        listOf("../secret.md", "Lore/../secret.md", "/secret.md", "Lore\\secret.md", "Lore//secret.md", "Lore/./x.md",
            "content://provider/x.md", "file:///vault/x.md", "a\u0000.md", "a\n.md", "a\r.md").forEach {
            assertFalse(it, VaultPolicy.relative(it))
        }
    }
    @Test fun excludesConfigurationHiddenDirectoriesAndSelfExports() {
        listOf(".obsidian/plugins/a.md", ".git/config.md", "Lore/.secret.md", "Scalajaca-Exports/result.md",
            "nested/Scalajaca-Exports/result.md", "Android/data/private.md").forEach {
            assertFalse(it, VaultPolicy.relative(it))
        }
    }
    @Test fun rejectsRootAndSiblingEscape() {
        assertNull(VaultPolicy.descendant("primary:Vault", "primary:Vault"))
        assertNull(VaultPolicy.descendant("primary:Vault", "primary:Vault2/file.md"))
        assertNull(VaultPolicy.descendant("primary:Vault", "ABCD-1234:Vault/file.md"))
        assertNull(VaultPolicy.descendant("primary:Vault", "primary:Vault/Lore/../../private.md"))
        assertFalse(VaultPolicy.root("primary:"))
        assertFalse(VaultPolicy.root("primary:Android/data"))
        assertFalse(VaultPolicy.root("primary:.obsidian"))
    }
    @Test fun depthAndLengthAreBounded() {
        assertTrue(VaultPolicy.relative((1..20).joinToString("/") { "a" }))
        assertFalse(VaultPolicy.relative((1..21).joinToString("/") { "a" }))
        assertTrue(VaultPolicy.segment("x".repeat(255)))
        assertFalse(VaultPolicy.segment("x".repeat(256)))
        assertFalse(VaultPolicy.relative((1..5).joinToString("/") { "x".repeat(230) }))
    }
    @Test fun exportAcceptsOnlySimpleMarkdownNames() {
        assertTrue(VaultPolicy.exportName("Podsumowanie sesji.md"))
        assertFalse(VaultPolicy.exportName("../original.md"))
        assertFalse(VaultPolicy.exportName(".secret.md"))
        assertFalse(VaultPolicy.exportName("original.txt"))
        assertFalse(VaultPolicy.exportName("a?.md"))
        assertFalse(VaultPolicy.exportName("a".repeat(81) + ".md"))
    }
}
