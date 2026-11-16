package com.meetlaud.app.infra.system

import android.app.backup.BackupAgent
import android.app.backup.BackupDataInput
import android.app.backup.BackupDataOutput
import android.app.backup.FullBackupDataOutput
import android.os.ParcelFileDescriptor
import com.meetlaud.domain.StoragePreferences

/**
 * The library goes into the device backup only when the person turned it on in Settings, as on iOS (D-002).
 * Models never go: data_extraction_rules.xml leaves them out, since they can be downloaded again and are huge.
 */
class LibraryBackupAgent : BackupAgent() {
    private val isIncluded: Boolean
        get() = getSharedPreferences("meetlaud", MODE_PRIVATE).getBoolean(StoragePreferences.BACKUP_INCLUDED_KEY, false)

    override fun onFullBackup(data: FullBackupDataOutput) {
        if (isIncluded) super.onFullBackup(data)
    }

    // Key-value backup is not used. Everything goes through the full backup above.
    override fun onBackup(oldState: ParcelFileDescriptor?, data: BackupDataOutput?, newState: ParcelFileDescriptor?) = Unit
    override fun onRestore(data: BackupDataInput?, appVersionCode: Int, newState: ParcelFileDescriptor?) = Unit
}
