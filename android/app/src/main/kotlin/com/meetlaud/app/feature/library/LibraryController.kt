package com.meetlaud.app.feature.library

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.meetlaud.app.feature.shared.RECORDING_SORT_KEY
import com.meetlaud.domain.Folder
import com.meetlaud.domain.FolderID
import com.meetlaud.domain.LibraryService
import com.meetlaud.domain.Preferences
import com.meetlaud.domain.Recording
import com.meetlaud.domain.RecordingSort
import com.meetlaud.domain.RecordingStatus
import com.meetlaud.domain.RecordingStore
import com.meetlaud.domain.SearchHit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Instant

/** The state of the library, shared by its screens, as LibraryController.swift. There is one for the life of the app. */
class LibraryController(
    val service: LibraryService,
    private val store: RecordingStore,
    private val defaults: Preferences,
    private val context: Context,
    private val scope: CoroutineScope,
) {
    var all by mutableStateOf<List<Recording>>(emptyList())
        private set
    var folders by mutableStateOf<List<Folder>>(emptyList())
        private set
    var isImporting by mutableStateOf(false)
        private set
    var showsFilePicker by mutableStateOf(false)
    var showsImportFailure by mutableStateOf(false)

    var sort: RecordingSort
        get() = defaults.string(RECORDING_SORT_KEY)?.let { RecordingSort.from(it) } ?: RecordingSort.NEWEST
        set(value) = defaults.setString(RECORDING_SORT_KEY, value.raw)

    init {
        scope.launch { store.observeRecordings().collect { all = it } }
        scope.launch { store.observeFolders().collect { folders = it } }
        scope.launch { runCatching { service.purgeExpiredTrash() } }
    }

    val active: List<Recording> get() = sort.sorted(all.filter { it.deletedAt == null && it.status == RecordingStatus.READY })

    val trashed: List<Recording> get() = all.filter { it.deletedAt != null }.sortedByDescending { it.deletedAt ?: Instant.now() }

    /** `null` is the main Recordings list. */
    fun recordings(folder: FolderID?): List<Recording> = active.filter { it.folderID == folder }

    suspend fun search(query: String): List<SearchHit> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return emptyList()
        return runCatching { store.search(trimmed) }.getOrDefault(emptyList())
    }

    // MARK: - Import

    fun presentFilePicker() {
        showsFilePicker = true
    }

    /**
     * Handles files from the picker and from "Open with" in other apps. Android hands over a content address, not a
     * path, so each one is copied into the cache first, and the copy is removed once the recording exists.
     */
    fun importFiles(uris: List<Uri>) {
        scope.launch {
            isImporting = true
            try {
                for (uri in uris) {
                    val title = displayName(uri)?.substringBeforeLast('.') ?: "Audio"
                    val copy = withContext(Dispatchers.IO) {
                        runCatching {
                            File(context.cacheDir, "import-${System.nanoTime()}").also { file ->
                                context.contentResolver.openInputStream(uri)!!.use { input -> file.outputStream().use { input.copyTo(it) } }
                            }
                        }.getOrNull()
                    }
                    val saved = copy?.let { runCatching { service.importAudio(it, title) }.getOrNull() }
                    copy?.delete()
                    if (saved == null) showsImportFailure = true
                }
            } finally {
                isImporting = false
            }
        }
    }

    private fun displayName(uri: Uri): String? = runCatching {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }.getOrNull() ?: uri.lastPathSegment
}
