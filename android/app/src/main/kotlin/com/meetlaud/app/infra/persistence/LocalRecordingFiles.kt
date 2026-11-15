package com.meetlaud.app.infra.persistence

import android.os.StatFs
import com.meetlaud.domain.RecordingFiles
import com.meetlaud.domain.RecordingID
import com.meetlaud.domain.StorageManaging
import com.meetlaud.domain.StorageUsage
import com.meetlaud.domain.uuidString
import java.io.File

/**
 * The app's folders, the same layout as iOS: recordings/<id>/{audio, recording.m4a, attachments}. Everything lives in
 * the app's private storage, which Android's backup leaves out (`allowBackup` is off, D-002).
 */
class LocalRecordingFiles(val root: File, private val cache: File) : RecordingFiles, StorageManaging {
    init {
        root.mkdirs()
    }

    val databaseFile: File get() = File(root, "meetlaud.sqlite")
    val modelsDirectory: File get() = File(root, "models")

    private fun folder(id: RecordingID) = File(File(root, "recordings"), id.rawValue.uuidString)

    override fun segmentsDirectory(id: RecordingID): File = File(folder(id), "audio").apply { mkdirs() }

    override fun audioFile(id: RecordingID): File = File(folder(id), "recording.m4a")

    override fun attachmentsDirectory(id: RecordingID): File = File(folder(id), "attachments").apply { mkdirs() }

    override fun prepare(id: RecordingID) {
        folder(id).mkdirs()
    }

    override fun copyAttachment(name: String, source: RecordingID, destination: RecordingID) {
        File(attachmentsDirectory(source), name).copyTo(File(attachmentsDirectory(destination), name))
    }

    override fun removeSegments(id: RecordingID) {
        File(folder(id), "audio").deleteRecursively()
    }

    override fun removeAll(id: RecordingID) {
        folder(id).deleteRecursively()
    }

    override fun hasSegments(id: RecordingID): Boolean =
        File(folder(id), "audio").listFiles()?.any { it.length() > 1 } ?: false

    override fun availableBytes(): Long = runCatching { StatFs(root.path).availableBytes }.getOrDefault(0)

    // MARK: - Storage

    private fun size(file: File): Long = if (!file.exists()) 0 else file.walkTopDown().filter { it.isFile }.sumOf { it.length() }

    override fun usage(): StorageUsage = StorageUsage(
        recordings = size(File(root, "recordings")),
        library = root.listFiles()?.filter { it.name.startsWith("meetlaud.sqlite") }?.sumOf { it.length() } ?: 0,
        models = size(modelsDirectory),
        cache = size(cache),
        available = availableBytes(),
    )

    override fun clearCache() {
        cache.listFiles()?.forEach { it.deleteRecursively() }
    }

    /** LibraryBackupAgent reads the same preference at backup time, so there is nothing per file to change (D-002). */
    override fun setBackupIncluded(included: Boolean) = Unit

    override fun removeEverything() {
        File(root, "recordings").deleteRecursively()
        clearCache()
    }
}
