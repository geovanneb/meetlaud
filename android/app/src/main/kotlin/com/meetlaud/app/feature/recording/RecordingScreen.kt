package com.meetlaud.app.feature.recording

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.meetlaud.app.designsystem.AlertButton
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.GlassCircleButton
import com.meetlaud.app.designsystem.IosAlert
import com.meetlaud.app.designsystem.IosMenu
import com.meetlaud.app.designsystem.MenuAction
import com.meetlaud.app.designsystem.Radius
import com.meetlaud.app.designsystem.RecordSymbol
import com.meetlaud.app.designsystem.SfIcon
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.designsystem.WaveformView
import com.meetlaud.app.designsystem.clock
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.routing.LocalRouter
import com.meetlaud.app.shell.NavigationBar
import com.meetlaud.domain.CaptureStatus
import com.meetlaud.domain.MarkerKind
import com.meetlaud.domain.PauseReason
import java.io.ByteArrayOutputStream

/** The recorder, full screen over everything, as RecordingScreen.swift. */
@Composable
fun RecordingScreen(controller: RecordingController) {
    val router = LocalRouter.current
    val snapshot = controller.snapshot
    val isPaused = snapshot.status is CaptureStatus.Paused
    var isAddingNote by remember { mutableStateOf(false) }
    var note by remember { mutableStateOf("") }
    val haptics = LocalHapticFeedback.current
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicturePreview()) { bitmap: Bitmap? ->
        bitmap ?: return@rememberLauncherForActivityResult
        val bytes = ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }.toByteArray()
        controller.addPhoto(bytes)
    }
    BackHandler { router.isRecorderPresented = false }

    Column(Modifier.fillMaxSize().background(Ds.background.value).testTag("screen.recorder").navigationBarsPadding().padding(bottom = Spacing.large)) {
        NavigationBar(
            title = snapshot.title,
            leading = { GlassCircleButton("chevron.down", L10n.Recorder.minimize, Modifier.testTag("recorder.minimize")) { router.isRecorderPresented = false } },
            trailing = {
                if (snapshot.status.isActive && controller.inputs.size > 1) {
                    var open by remember { mutableStateOf(false) }
                    Box {
                        GlassCircleButton("mic", L10n.Recorder.microphone) { open = true }
                        IosMenu(open, { open = false }, controller.inputs.map { input -> MenuAction(input.name) { controller.select(input) } })
                    }
                }
            },
        )
        Spacer(Modifier.weight(1f))
        Column(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}.testTag("recorder.time"), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
            Text(snapshot.recorded.clock, style = DsType.display, color = Ds.primaryText.value)
            Text(statusText(snapshot.status), style = DsType.meta, color = Ds.secondaryText.value)
        }
        Spacer(Modifier.height(Spacing.large))
        WaveformView(controller.levels, snapshot.status == CaptureStatus.Recording, Modifier.fillMaxWidth().height(96.dp).padding(horizontal = Spacing.medium))
        Spacer(Modifier.height(Spacing.large))
        if (snapshot.status == CaptureStatus.Paused(PauseReason.INTERRUPTION)) Notice(L10n.Recorder.interruptedMessage, "phone.down")
        if (snapshot.isStorageLow) Notice(L10n.Recorder.storageLow, "externaldrive.badge.exclamationmark")
        LazyColumn(Modifier.fillMaxWidth().heightIn(min = 60.dp, max = 180.dp)) {
            items(snapshot.markers.reversed(), key = { it.id.toString() }) { marker ->
                Row(Modifier.padding(horizontal = Spacing.medium, vertical = Spacing.small).semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
                    Text(marker.time.clock, style = DsType.timestamp, color = Ds.secondaryText.value)
                    SfIcon(marker.kind.symbol, tint = Ds.action.value)
                    Text(marker.text ?: marker.kind.title, style = DsType.rowTitle, color = Ds.primaryText.value)
                }
            }
        }
        Spacer(Modifier.height(Spacing.large))
        AnimatedContent(snapshot.status == CaptureStatus.Idle, transitionSpec = { (fadeIn() + slideInVertically { it / 8 }) togetherWith fadeOut() }, label = "controls") { idle ->
            if (idle) {
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    CircleControl(L10n.Home.record, large = true, tag = "recorder.start", onClick = { controller.record() }) { RecordSymbol(size = 30.dp) }
                }
            } else {
                val enabled = snapshot.status != CaptureStatus.Finishing
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.large)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xLarge), verticalAlignment = Alignment.CenterVertically) {
                        CircleControl(L10n.Recorder.flag, tag = "recorder.flag", enabled = enabled, onClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            controller.flag()
                        }) { SfIcon("flag", size = 26.dp) }
                        CircleControl(L10n.Recorder.photo, enabled = enabled, onClick = { camera.launch(null) }) { SfIcon("camera", size = 26.dp) }
                        CircleControl(L10n.Recorder.addNote, tag = "recorder.note", enabled = enabled, onClick = { isAddingNote = true }) { SfIcon("square.and.pencil", size = 26.dp) }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xLarge), verticalAlignment = Alignment.CenterVertically) {
                        CircleControl(if (isPaused) L10n.Recorder.resume else L10n.Recorder.pause, tag = "recorder.pause", enabled = enabled, onClick = { controller.togglePause() }) {
                            SfIcon(if (isPaused) "play.fill" else "pause.fill", size = 26.dp)
                        }
                        CircleControl(L10n.Recorder.stop, large = true, tag = "recorder.stop", enabled = enabled, onClick = { controller.stop() }) {
                            Box(Modifier.width(26.dp).height(26.dp).clip(RoundedCornerShape(5.dp)).background(Ds.record.value))
                        }
                    }
                }
            }
        }
    }

    if (isAddingNote) {
        IosAlert(
            title = L10n.Recorder.addNote,
            buttons = listOf(
                AlertButton(L10n.Common.cancel, AlertButton.Role.CANCEL) { note = "" },
                AlertButton(L10n.Common.save) {
                    controller.addNote(note)
                    note = ""
                },
            ),
            onDismiss = { isAddingNote = false },
            field = {
                OutlinedTextField(
                    note, { note = it }, placeholder = { Text(L10n.Recorder.notePlaceholder, style = DsType.rowTitle) },
                    singleLine = true, textStyle = DsType.rowTitle, shape = RoundedCornerShape(10.dp),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                    modifier = Modifier.fillMaxWidth().testTag("recorder.note.field"),
                )
            },
        )
    }
}

private fun statusText(status: CaptureStatus): String = when (status) {
    CaptureStatus.Idle -> L10n.Recorder.statusReady
    CaptureStatus.Recording -> L10n.Recorder.statusRecording
    is CaptureStatus.Paused -> if (status.reason == PauseReason.USER) L10n.Recorder.statusPaused else L10n.Recorder.statusInterrupted
    CaptureStatus.Finishing -> L10n.Recorder.statusFinishing
}

@Composable
private fun Notice(text: String, symbol: String) {
    Row(
        Modifier.padding(horizontal = Spacing.medium).fillMaxWidth().clip(RoundedCornerShape(Radius.medium)).background(Ds.surface.value).padding(Spacing.medium),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.small),
    ) {
        SfIcon(symbol, size = DsType.meta.fontSize)
        Text(text, style = DsType.meta, color = Ds.primaryText.value)
    }
    Spacer(Modifier.height(Spacing.small))
}

/** A round glass control: 60 points, or 84 for the main one. */
@Composable
private fun CircleControl(title: String, large: Boolean = false, tag: String? = null, enabled: Boolean = true, onClick: () -> Unit, icon: @Composable () -> Unit) {
    com.meetlaud.app.designsystem.GlassCircle(
        label = title,
        diameter = if (large) 84.dp else 60.dp,
        modifier = if (tag != null) Modifier.testTag(tag) else Modifier,
        enabled = enabled,
        onClick = onClick,
        content = icon,
    )
}

val MarkerKind.symbol: String
    get() = when (this) {
        MarkerKind.FLAG -> "flag.fill"
        MarkerKind.NOTE -> "square.and.pencil"
        MarkerKind.PHOTO -> "camera.fill"
    }

val MarkerKind.title: String
    get() = when (this) {
        MarkerKind.FLAG -> L10n.Recorder.flag
        MarkerKind.NOTE -> L10n.Recorder.addNote
        MarkerKind.PHOTO -> L10n.Recorder.photo
    }
