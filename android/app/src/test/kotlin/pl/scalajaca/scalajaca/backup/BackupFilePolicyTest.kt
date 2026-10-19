package pl.scalajaca.scalajaca.backup

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicBoolean

class BackupFilePolicyTest {
    @Test fun cancelBeforeFinalBlockCannotReportSuccess() {
        val gate = BackupCompletionGate()
        assertTrue(gate.cancel())
        assertTrue(gate.cancelled)
        assertFalse(gate.complete())
        assertFalse(gate.cancel())
    }
    @Test fun closeAfterCompletedCopyDoesNotRewriteItsOutcome() {
        val gate = BackupCompletionGate()
        assertTrue(gate.complete())
        assertFalse(gate.cancel())
        assertFalse(gate.cancelled)
        assertFalse(gate.complete())
    }
    @Test fun concurrentCancelAndFinalBlockHaveOneWinner() {
        repeat(100) {
            val gate = BackupCompletionGate()
            val start = CountDownLatch(1)
            val success = AtomicBoolean(false)
            val writer = Thread { start.await(); success.set(gate.complete()) }
            val closer = Thread { start.await(); gate.cancel() }
            writer.start(); closer.start(); start.countDown()
            writer.join(); closer.join()
            assertNotEquals(gate.cancelled, success.get())
        }
    }
    @Test fun archiveLimitUsesLongAndAcceptsExactlyTwoGiB() {
        assertEquals(2147483648L, BackupFilePolicy.MAX_ARCHIVE)
        assertTrue(BackupFilePolicy.growth(2147483647L, 1))
        assertTrue(BackupFilePolicy.growth(2147483648L, 0))
        assertFalse(BackupFilePolicy.growth(2147483648L, 1))
        assertFalse(BackupFilePolicy.growth(2147483649L, 0))
    }
    @Test fun rejectsArithmeticOverflowAndNegativeCounts() {
        assertFalse(BackupFilePolicy.growth(Long.MAX_VALUE, 1))
        assertFalse(BackupFilePolicy.growth(Long.MIN_VALUE, 1))
        assertFalse(BackupFilePolicy.growth(-1, 1))
        assertFalse(BackupFilePolicy.growth(0, -1))
    }
    @Test fun writeBackpressureHasHardChunkLimit() {
        assertTrue(BackupFilePolicy.growth(0, 0))
        assertTrue(BackupFilePolicy.growth(0, 262144))
        assertFalse(BackupFilePolicy.growth(0, 262145))
        assertFalse(BackupFilePolicy.growth(BackupFilePolicy.MAX_ARCHIVE - 10, 11))
    }
    @Test fun readsAreBoundedAndZeroIsReservedForEof() {
        assertTrue(BackupFilePolicy.readSize(1))
        assertTrue(BackupFilePolicy.readSize(65536))
        assertFalse(BackupFilePolicy.readSize(0))
        assertFalse(BackupFilePolicy.readSize(-1))
        assertFalse(BackupFilePolicy.readSize(65537))
    }
    @Test fun stageCleanupMatchesOnlyGeneratedCiphertextFiles() {
        assertTrue(BackupFilePolicy.stageName("77bc90f8-b131-4a70-9d10-d386c9cba001.stage"))
        listOf("../77bc90f8-b131-4a70-9d10-d386c9cba001.stage", "secret.md", "ciphertext.stage", ".stage",
            "77bc90f8-b131-4a70-9d10-d386c9cba001.stage/child", "77bc90f8-b131-4a70-9d10-d386c9cba001.stage.tmp").forEach {
            assertFalse(it, BackupFilePolicy.stageName(it))
        }
    }
    @Test fun exportRequiresSimpleScalabackupFilename() {
        assertTrue(BackupFilePolicy.filename("Scalajaca-2026-10-19.scalabackup"))
        assertTrue(BackupFilePolicy.filename("Moja pełna kopia.scalabackup"))
        listOf("../x.scalabackup", "x\\x.scalabackup", "/x.scalabackup", "content://x.scalabackup", ".scalabackup",
            ".hidden.scalabackup", "x.md", "x.scalabackup\n", "x\u0000.scalabackup", "x?.scalabackup",
            "x".repeat(121) + ".scalabackup").forEach { assertFalse(it, BackupFilePolicy.filename(it)) }
    }
}
