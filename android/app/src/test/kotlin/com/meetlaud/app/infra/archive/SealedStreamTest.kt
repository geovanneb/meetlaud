package com.meetlaud.app.infra.archive

import com.meetlaud.domain.ArchiveError
import com.meetlaud.domain.ArchiveException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/** The archive format must stay the iOS one, byte for byte, so a library can move between the two apps. */
class SealedStreamTest {
    @get:Rule val folder = TemporaryFolder()

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }

    @Test fun keyMatchesThePublishedTestVector() {
        // RFC 7914, section 11: PBKDF2-HMAC-SHA256, "passwd", "salt", one iteration.
        val key = SealedFormat.key("passwd", "salt".toByteArray(), 1)
        assertEquals("55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc", hex(key))
    }

    private fun entries(file: File, password: String): List<Pair<String, ByteArray>> = SealedReader(file, password).use { reader ->
        buildList {
            while (true) {
                val length = reader.read(4).fold(0) { value, byte -> (value shl 8) or (byte.toInt() and 0xFF) }
                if (length == 0) {
                    reader.requireEnd()
                    break
                }
                val name = String(reader.read(length))
                val size = reader.read(8).fold(0L) { value, byte -> (value shl 8) or (byte.toLong() and 0xFF) }
                add(name to reader.read(size.toInt()))
            }
        }
    }

    @Test fun readsAnArchiveTheIosAppWrote() {
        // Written by ios/Packages/Infrastructure/Archive/Sources/SealedStream.swift, password "correct horse".
        val file = File(javaClass.getResource("/archive/from-ios.meetlaudbackup")!!.toURI())
        val read = entries(file, "correct horse")
        assertEquals(listOf("database.sqlite", "recordings/A/audio.m4a"), read.map { it.first })
        assertEquals("fictional database", String(read[0].second))
        assertArrayEquals(ByteArray(300) { (it % 251).toByte() }, read[1].second)
    }

    @Test fun aWrongPasswordIsToldApartFromDamage() {
        val file = File(javaClass.getResource("/archive/from-ios.meetlaudbackup")!!.toURI())
        expect(ArchiveError.WRONG_PASSWORD) { entries(file, "wrong") }
    }

    private fun writeLarge(file: File): ByteArray {
        val body = ByteArray(2_500_000) { (it % 253).toByte() }
        val writer = SealedWriter(file, "correct horse")
        val name = "recordings/B/audio.m4a".toByteArray()
        writer.write(SealedFormat.intBytes(name.size) + name + SealedFormat.longBytes(body.size.toLong()) + body)
        writer.write(SealedFormat.intBytes(0))
        writer.finish()
        return body
    }

    @Test fun roundTripsAcrossSeveralBlocks() {
        val file = folder.newFile("large.meetlaudbackup")
        val body = writeLarge(file)
        val read = entries(file, "correct horse")
        assertEquals("recordings/B/audio.m4a", read.single().first)
        assertArrayEquals(body, read.single().second)
        // Kept for the cross-check against the Swift reader, when asked for.
        System.getenv("SEALED_OUT")?.let { file.copyTo(File(it), overwrite = true) }
    }

    @Test fun aCutFileIsDamaged() {
        val file = folder.newFile("cut.meetlaudbackup")
        writeLarge(file)
        // Dropping the last block must fail, even though every block left is valid on its own.
        val bytes = file.readBytes()
        val header = SealedFormat.magic.size + 4 + SealedFormat.SALT_SIZE + SealedFormat.NONCE_SIZE
        val fullBlock = 5 + SealedFormat.NONCE_SIZE + SealedFormat.BLOCK_SIZE + 16
        file.writeBytes(bytes.copyOf(header + 2 * fullBlock))
        expect(ArchiveError.DAMAGED) { entries(file, "correct horse") }
    }

    @Test fun pathsCannotLeaveTheSideFolder() {
        val archive = LibraryArchive(folder.root, NoSnapshots)
        val side = folder.newFolder("side")
        for (name in listOf("../x", "recordings/../../x", "/etc/x", "recordings/", "other/x", "recordings//x", "recordings/./x")) {
            expect(ArchiveError.DAMAGED) { archive.destination(name, side) }
        }
        assertEquals(File(side, "recordings/A/audio.m4a").path, archive.destination("recordings/A/audio.m4a", side).path)
    }

    private fun expect(error: ArchiveError, block: () -> Unit) {
        try {
            block()
            fail("Expected $error")
        } catch (thrown: ArchiveException) {
            assertEquals(error, thrown.error)
        }
    }

    private object NoSnapshots : com.meetlaud.domain.DatabaseSnapshots {
        override suspend fun writeSnapshot(file: File, includingVoicePrints: Boolean) = Unit
        override suspend fun restoreSnapshot(file: File) = Unit
        override suspend fun eraseEverything() = Unit
    }
}
