package com.meetlaud.app.feature.shared

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.meetlaud.app.designsystem.AlertButton
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.IosAlert
import com.meetlaud.app.localization.L10n

/** Asks for a name. Used for recordings and folders alike, as NamePrompt in RecordingRow.swift. */
@Composable
fun NamePrompt(title: String, name: String, onName: (String) -> Unit, onDismiss: () -> Unit, onSave: () -> Unit) {
    IosAlert(
        title = title,
        buttons = listOf(AlertButton(L10n.Common.cancel, AlertButton.Role.CANCEL), AlertButton(L10n.Common.save, tag = "name.save", onClick = onSave)),
        onDismiss = onDismiss,
        field = {
            OutlinedTextField(
                name, onName, placeholder = { Text(L10n.Library.namePlaceholder, style = DsType.rowTitle) },
                singleLine = true, textStyle = DsType.rowTitle, shape = RoundedCornerShape(10.dp),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                modifier = Modifier.fillMaxWidth().testTag("name.field"),
            )
        },
    )
}
