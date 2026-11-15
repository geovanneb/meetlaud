package com.meetlaud.app.feature.library

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import com.meetlaud.app.designsystem.AlertButton
import com.meetlaud.app.designsystem.IosAlert
import com.meetlaud.app.localization.L10n

/** The file picker and its errors, attached once at the root of the app, as ImportPrompts.swift. */
@Composable
fun ImportPrompts(library: LibraryController) {
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) library.importFiles(uris)
    }
    LaunchedEffect(library.showsFilePicker) {
        if (library.showsFilePicker) {
            library.showsFilePicker = false
            // Audio and video, as `.audio` and `.movie` on iOS.
            picker.launch(arrayOf("audio/*", "video/*"))
        }
    }
    if (library.showsImportFailure) {
        IosAlert(L10n.Library.importFailed, L10n.Library.importFailedMessage, listOf(AlertButton(L10n.Common.ok, AlertButton.Role.CANCEL)), onDismiss = { library.showsImportFailure = false })
    }
}
