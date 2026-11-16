package com.meetlaud.domain

import java.io.File
import java.time.Duration
import java.time.Instant

enum class LibraryError { NOTHING_TO_MERGE, RECORDING_NOT_FOUND }

class LibraryException(val error: LibraryError) : Exception(error.name)

/** What a person can do to their recordings once they exist. */
class LibraryService(
    private val store: RecordingStore,
    private val files: RecordingFiles,
    private val audio: AudioProcessor,
    private val now: () -> Instant = { Instant.now() },
) {
    companion object {
        /** Trashed recordings stay this long, so that a mistake can be undone. */
        val TRASH_RETENTION: Duration = Duration.ofDays(30)
    }

    // MARK: - Organize

    suspend fun rename(id: RecordingID, title: String) {
        val trimmed = title.trimmedWhitespace()
        if (trimmed.isEmpty()) return
        val recording = store.recording(id) ?: return
        store.update(recording.copy(title = trimmed))
    }

    suspend fun move(ids: List<RecordingID>, folder: FolderID?) = edit(ids) { it.copy(folderID = folder) }

    suspend fun createFolder(name: String): Folder? {
        val trimmed = name.trimmedWhitespace()
        if (trimmed.isEmpty()) return null
        val folder = Folder(name = trimmed, createdAt = now())
        store.insert(folder)
        return folder
    }

    suspend fun rename(folder: Folder, name: String) {
        val trimmed = name.trimmedWhitespace()
        if (trimmed.isEmpty()) return
        store.update(folder.copy(name = trimmed))
    }

    /** Recordings inside are kept, and return to the main list. */
    suspend fun delete(folder: Folder) = store.deleteFolder(folder.id)

    // MARK: - Trash

    suspend fun trash(ids: List<RecordingID>) {
        val date = now()
        edit(ids) { it.copy(deletedAt = date) }
    }

    suspend fun restore(ids: List<RecordingID>) = edit(ids) { it.copy(deletedAt = null) }

    suspend fun deleteForever(ids: List<RecordingID>) {
        for (id in ids) {
            store.delete(id)
            runCatching { files.removeAll(id) }
        }
    }

    suspend fun emptyTrash() = deleteForever(store.trashedRecordings().map { it.id })

    /** Runs at launch. Returns how many recordings were removed. */
    suspend fun purgeExpiredTrash(): Int {
        val limit = now().minus(TRASH_RETENTION)
        val expired = store.trashedRecordings().filter { (it.deletedAt ?: Instant.MAX) < limit }
        deleteForever(expired.map { it.id })
        return expired.size
    }

    // MARK: - Import

    /** Copies audio from outside the app into a new recording. */
    suspend fun importAudio(source: File, title: String): Recording {
        val id = RecordingID()
        files.prepare(id)
        try {
            val duration = audio.importAudio(source, files.audioFile(id))
            val recording = Recording(id = id, title = title, createdAt = now(), duration = maxOf(0.0, duration))
            store.insert(recording)
            return recording
        } catch (error: Exception) {
            runCatching { files.removeAll(id) }
            throw error
        }
    }

    // MARK: - Merge

    /** Joins recordings in time order into a new one, and moves the originals to the trash, so nothing is lost. */
    suspend fun merge(ids: List<RecordingID>): Recording {
        val recordings = ids.map { store.recording(it) ?: throw LibraryException(LibraryError.RECORDING_NOT_FOUND) }
            .sortedBy { it.createdAt }
        val first = recordings.firstOrNull()
        if (recordings.size <= 1 || first == null) throw LibraryException(LibraryError.NOTHING_TO_MERGE)

        val id = RecordingID()
        files.prepare(id)
        try {
            val duration = audio.merge(recordings.map { files.audioFile(it.id) }, files.audioFile(id))
            val merged = Recording(
                id = id,
                title = first.title,
                createdAt = first.createdAt,
                duration = maxOf(0.0, duration),
                folderID = first.folderID,
                attendees = recordings.flatMap { it.attendees }.distinct(),
            )
            store.insert(merged)
            copyMarkers(recordings, id)
            trash(recordings.map { it.id })
            return merged
        } catch (error: Exception) {
            runCatching { store.delete(id) }
            runCatching { files.removeAll(id) }
            throw error
        }
    }

    private suspend fun copyMarkers(recordings: List<Recording>, id: RecordingID) {
        var offset = 0.0
        for (recording in recordings) {
            for (marker in store.markers(recording.id)) {
                marker.attachment?.let { files.copyAttachment(it, recording.id, id) }
                store.insert(Marker(recordingID = id, time = marker.time + offset, kind = marker.kind, text = marker.text, attachment = marker.attachment))
            }
            offset += recording.duration
        }
    }

    private suspend fun edit(ids: List<RecordingID>, change: (Recording) -> Recording) {
        for (id in ids) {
            val recording = store.recording(id) ?: continue
            store.update(change(recording))
        }
    }
}
