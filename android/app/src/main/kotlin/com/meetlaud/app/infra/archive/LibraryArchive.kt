package com.meetlaud.app.infra.archive

import com.meetlaud.domain.ArchiveError
import com.meetlaud.domain.ArchiveException
import com.meetlaud.domain.DatabaseSnapshots
import com.meetlaud.domain.LibraryArchiver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID
import kotlin.coroutines.coroutineContext

/** Moves a whole library to another device, as one password-protected file, with no cloud in between. As LibraryArchive.swift. */
class LibraryArchive(private val root: File, private val snapshots: DatabaseSnapshots) : LibraryArchiver {
    private companion object {
        const val DATABASE_ENTRY = "database.sqlite"
        const val RECORDINGS_FOLDER = "recordings"
        const val COPY_SIZE = 256 * 1024
    }

    override suspend fun export(file: File, password: String, includingVoicePrints: Boolean, progress: (Double) -> Unit) {
        val work = scratchFolder()
        try {
            val database = File(work, DATABASE_ENTRY)
            snapshots.writeSnapshot(database, includingVoicePrints)
            withContext(Dispatchers.IO) {
                val entries = listOf(DATABASE_ENTRY to database) + recordingFiles()
                val total = maxOf(1L, entries.sumOf { it.second.length() })
                var done = 0L
                val writer = SealedWriter(file, password)
                try {
                    for ((name, source) in entries) {
                        coroutineContext.ensureActive()
                        val label = name.toByteArray(Charsets.UTF_8)
                        writer.write(SealedFormat.intBytes(label.size) + label + SealedFormat.longBytes(source.length()))
                        source.inputStream().use { input ->
                            val buffer = ByteArray(COPY_SIZE)
                            while (true) {
                                val read = input.read(buffer)
                                if (read <= 0) break
                                coroutineContext.ensureActive()
                                writer.write(buffer, read)
                                done += read
                                progress(done.toDouble() / total)
                            }
                        }
                    }
                    writer.write(SealedFormat.intBytes(0))
                    writer.finish()
                } catch (error: Throwable) {
                    writer.abandon()
                    throw error
                }
            }
            progress(1.0)
        } finally {
            work.deleteRecursively()
        }
    }

    override suspend fun restore(file: File, password: String, progress: (Double) -> Unit) {
        val work = scratchFolder()
        try {
            // Everything lands in a side folder first. A wrong password or a damaged file must leave the library as it was.
            withContext(Dispatchers.IO) { extract(file, password, work, progress) }
            val database = File(work, DATABASE_ENTRY)
            if (!database.exists()) throw ArchiveException(ArchiveError.DAMAGED)
            coroutineContext.ensureActive()
            snapshots.restoreSnapshot(database)
            withContext(Dispatchers.IO) {
                val live = File(root, RECORDINGS_FOLDER)
                live.deleteRecursively()
                val restored = File(work, RECORDINGS_FOLDER)
                if (restored.exists() && !restored.renameTo(live)) {
                    restored.copyRecursively(live, overwrite = true)
                }
            }
            progress(1.0)
        } finally {
            work.deleteRecursively()
        }
    }

    private fun scratchFolder(): File = File(root, "archive-${UUID.randomUUID().toString().uppercase()}").apply { mkdirs() }

    private fun recordingFiles(): List<Pair<String, File>> {
        val folder = File(root, RECORDINGS_FOLDER)
        if (!folder.exists()) return emptyList()
        val prefix = root.canonicalPath + "/"
        return folder.walkTopDown().filter { it.isFile }.map { it.canonicalPath.removePrefix(prefix) to it }.toList()
    }

    private suspend fun extract(file: File, password: String, folder: File, progress: (Double) -> Unit) {
        SealedReader(file, password).use { reader ->
            val total = maxOf(1L, file.length())
            val destinations = mutableSetOf<String>()
            while (true) {
                coroutineContext.ensureActive()
                val length = decode(reader.read(4))
                if (length == 0L) {
                    reader.requireEnd()
                    return
                }
                if (length > 4096) throw ArchiveException(ArchiveError.DAMAGED)
                val name = runCatching { Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(reader.read(length.toInt()))).toString() }
                    .getOrElse { throw ArchiveException(ArchiveError.DAMAGED) }
                val target = destination(name, folder)
                if (!destinations.add(target.path)) throw ArchiveException(ArchiveError.DAMAGED)
                var remaining = decode(reader.read(8))
                if (remaining < 0) throw ArchiveException(ArchiveError.DAMAGED)
                target.parentFile?.mkdirs()
                target.outputStream().use { output ->
                    while (remaining > 0) {
                        coroutineContext.ensureActive()
                        val step = minOf(remaining, COPY_SIZE.toLong()).toInt()
                        output.write(reader.read(step))
                        remaining -= step
                        progress(minOf(0.95, reader.bytesRead.toDouble() / total))
                    }
                }
            }
        }
    }

    private fun decode(bytes: ByteArray): Long = bytes.fold(0L) { value, byte -> (value shl 8) or (byte.toLong() and 0xFF) }

    /**
     * A password protects the file from others, and this protects the phone from the file. Whoever made it could have
     * written any path, and nothing may land outside the side folder.
     */
    internal fun destination(name: String, folder: File): File {
        val parts = name.split("/")
        val isAllowed = name == DATABASE_ENTRY || (parts.first() == RECORDINGS_FOLDER && parts.size > 1)
        if (!isAllowed || name.contains('\u0000') || name.startsWith("/") || parts.any { it == ".." || it == "." || it.isEmpty() }) {
            throw ArchiveException(ArchiveError.DAMAGED)
        }
        return parts.fold(folder) { parent, part -> File(parent, part) }
    }
}
