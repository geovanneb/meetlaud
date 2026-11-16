package com.meetlaud.app.feature.settings

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.meetlaud.domain.ArchiveError
import com.meetlaud.domain.ArchiveException
import com.meetlaud.domain.ExportFileName
import com.meetlaud.domain.LibraryArchiver
import com.meetlaud.domain.LocalNotifier
import com.meetlaud.domain.Preferences
import com.meetlaud.domain.StorageManaging
import com.meetlaud.domain.StoragePreferences
import com.meetlaud.domain.StorageUsage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.time.LocalDate

/** Storage, moving the library, and erasing it, as SystemController.swift. The app decides how to stop its own work. */
class SystemController(
    private val storage: StorageManaging,
    private val archiver: LibraryArchiver,
    private val notifier: LocalNotifier,
    private val defaults: Preferences,
    private val exportFolder: () -> File,
) {
    sealed interface ArchiveOutcome {
        data object Idle : ArchiveOutcome
        data class Working(val fraction: Double) : ArchiveOutcome
        data class Exported(val file: File) : ArchiveOutcome
        data object Restored : ArchiveOutcome
        data class Failed(val reason: Reason) : ArchiveOutcome
    }

    enum class Reason { RECORDING, WRONG_PASSWORD, DAMAGED, INCOMPATIBLE, OTHER }

    var usage by mutableStateOf<StorageUsage?>(null)
        private set
    var isBackupIncluded by mutableStateOf(defaults.bool(StoragePreferences.BACKUP_INCLUDED_KEY) == true)
        private set
    var archive by mutableStateOf<ArchiveOutcome>(ArchiveOutcome.Idle)
        private set
    var isErasing by mutableStateOf(false)
        private set

    private var pause: suspend () -> Boolean = { false }
    private var resume: suspend () -> Unit = {}
    private var erase: suspend () -> Unit = {}

    /** Set once the app is built, since these reach back into it. */
    fun connect(pauseAllWork: suspend () -> Boolean, resumeAllWork: suspend () -> Unit, eraseEverything: suspend () -> Unit) {
        pause = pauseAllWork
        resume = resumeAllWork
        erase = eraseEverything
    }

    suspend fun refreshUsage() {
        usage = withContext(Dispatchers.IO) { storage.usage() }
    }

    suspend fun clearCache() {
        withContext(Dispatchers.IO) { storage.clearCache() }
        refreshUsage()
    }

    fun changeBackupIncluded(included: Boolean) {
        if (runCatching { storage.setBackupIncluded(included) }.isFailure) return
        isBackupIncluded = included
        defaults.setBool(StoragePreferences.BACKUP_INCLUDED_KEY, included)
    }

    suspend fun requestNotificationAccess(): Boolean = notifier.requestAccess()

    fun resetArchive() {
        (archive as? ArchiveOutcome.Exported)?.file?.delete()
        archive = ArchiveOutcome.Idle
    }

    suspend fun exportLibrary(password: String, includingVoicePrints: Boolean) {
        if (!pause()) {
            archive = ArchiveOutcome.Failed(Reason.RECORDING)
            return
        }
        archive = ArchiveOutcome.Working(0.0)
        val file = File(exportFolder(), ExportFileName.safe("Library ${LocalDate.now()}", "meetlaudbackup"))
        archive = try {
            archiver.export(file, password, includingVoicePrints) { fraction -> report(fraction) }
            ArchiveOutcome.Exported(file)
        } catch (_: Exception) {
            file.delete()
            ArchiveOutcome.Failed(Reason.OTHER)
        }
        resume()
    }

    suspend fun restoreLibrary(file: File, password: String) {
        if (!pause()) {
            archive = ArchiveOutcome.Failed(Reason.RECORDING)
            return
        }
        archive = ArchiveOutcome.Working(0.0)
        archive = try {
            archiver.restore(file, password) { fraction -> report(fraction) }
            ArchiveOutcome.Restored
        } catch (error: ArchiveException) {
            ArchiveOutcome.Failed(
                when (error.error) {
                    ArchiveError.WRONG_PASSWORD -> Reason.WRONG_PASSWORD
                    ArchiveError.INCOMPATIBLE -> Reason.INCOMPATIBLE
                    ArchiveError.DAMAGED -> Reason.DAMAGED
                },
            )
        } catch (_: Exception) {
            ArchiveOutcome.Failed(Reason.OTHER)
        }
        resume()
    }

    private fun report(fraction: Double) {
        if (archive is ArchiveOutcome.Working) archive = ArchiveOutcome.Working(fraction)
    }

    /** Returns false when it could not run, which only happens during a recording. */
    suspend fun eraseEverything(): Boolean {
        isErasing = true
        try {
            if (!pause()) return false
            val succeeded = runCatching { erase() }.isSuccess
            resume()
            return succeeded
        } finally {
            isErasing = false
        }
    }
}
