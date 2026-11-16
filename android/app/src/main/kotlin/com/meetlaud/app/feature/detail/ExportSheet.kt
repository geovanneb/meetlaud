package com.meetlaud.app.feature.detail

import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.StaticLayout
import android.text.TextPaint
import android.text.style.AbsoluteSizeSpan
import android.text.style.StyleSpan
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.FormRow
import com.meetlaud.app.designsystem.FormSection
import com.meetlaud.app.designsystem.FormToggle
import com.meetlaud.app.designsystem.IosSheet
import com.meetlaud.app.designsystem.PrimaryAction
import com.meetlaud.app.designsystem.ProgressRing
import com.meetlaud.app.designsystem.SfIcon
import com.meetlaud.app.designsystem.SheetBar
import com.meetlaud.app.designsystem.SheetBody
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.designsystem.TextAction
import com.meetlaud.app.feature.shared.Sharing
import com.meetlaud.app.localization.L10n
import com.meetlaud.domain.ExportFileName
import com.meetlaud.domain.ExportOptions
import com.meetlaud.domain.TranscriptFormat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

private sealed interface ExportChoice {
    data object Audio : ExportChoice
    data class Transcript(val format: TranscriptFormat) : ExportChoice
    data object SummaryMarkdown : ExportChoice
    data object SummaryPdf : ExportChoice
}

/** Picks what to share, as ExportSheet.swift. The file exists only while this sheet is open. */
@Composable
fun ExportSheet(model: DetailModel, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val choices = remember(model.segments.size, model.selectedSummary, model.hasAudio) {
        buildList {
            if (model.segments.isNotEmpty()) TranscriptFormat.entries.forEach { add(ExportChoice.Transcript(it) to "${L10n.Transcript.title} (${it.fileExtension.uppercase()})") }
            if (model.selectedSummary != null) {
                add(ExportChoice.SummaryMarkdown to "${L10n.Summary.title} (MD)")
                add(ExportChoice.SummaryPdf to "${L10n.Summary.title} (PDF)")
            }
            if (model.hasAudio) add(ExportChoice.Audio to "${L10n.Detail.audio} (M4A)")
        }
    }
    var choice by remember { mutableStateOf<ExportChoice>(choices.firstOrNull()?.first ?: ExportChoice.Transcript(TranscriptFormat.TXT)) }
    var options by remember { mutableStateOf(ExportOptions()) }
    var file by remember { mutableStateOf<File?>(null) }
    var failed by remember { mutableStateOf(false) }
    val folder = remember { File(Sharing.exportFolder(context), "export-${UUID.randomUUID()}") }
    DisposableEffect(Unit) { onDispose { folder.deleteRecursively() } }

    LaunchedEffect(choice, options, failed) {
        if (failed) return@LaunchedEffect
        file = null
        folder.deleteRecursively()
        file = runCatching { withContext(Dispatchers.IO) { prepare(model, choice, options, folder) } }.getOrElse {
            failed = true
            folder.deleteRecursively()
            null
        }
    }

    IosSheet(onDismiss) {
        SheetBar(L10n.Detail.export, leading = { TextAction(L10n.Common.done, color = Ds.primaryText.value, onClick = onDismiss) })
        Box(Modifier.weight(1f)) {
            SheetBody(Modifier.padding(top = Spacing.medium).testTag("screen.export")) {
                FormSection(L10n.Detail.exportWhat) {
                    choices.forEachIndexed { index, (value, title) ->
                        FormRow(divider = index < choices.lastIndex, onClick = { choice = value; failed = false }) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(title, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f))
                                if (value == choice) SfIcon("checkmark", tint = Ds.action.value)
                            }
                        }
                    }
                }
                val usesOptions = (choice as? ExportChoice.Transcript)?.format?.usesOptions == true
                if (usesOptions) {
                    FormSection {
                        FormToggle(L10n.Detail.exportSpeakers, options.includesSpeakers, { options = options.copy(includesSpeakers = it) })
                        FormToggle(L10n.Detail.exportTimestamps, options.includesTimestamps, { options = options.copy(includesTimestamps = it) }, divider = false)
                    }
                }
            }
        }
        // Outside the form, so that the one action on this page never scrolls away.
        Box(Modifier.fillMaxWidth().padding(Spacing.medium), contentAlignment = Alignment.Center) {
            val ready = file
            when {
                ready != null -> PrimaryAction(L10n.Detail.exportShare, Modifier.fillMaxWidth().testTag("export.share"), symbol = "square.and.arrow.up") {
                    Sharing.shareFile(context, ready, mime(ready))
                }
                failed -> Column(Modifier.testTag("export.failure"), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.small)) {
                    Text(L10n.Detail.exportFailed, style = DsType.meta, color = Ds.secondaryText.value, textAlign = TextAlign.Center)
                    PrimaryAction(L10n.Detail.exportRetry) { failed = false }
                }
                else -> ProgressRing(null)
            }
        }
    }
}

private fun mime(file: File): String = when (file.extension) {
    "m4a" -> "audio/mp4"
    "pdf" -> "application/pdf"
    "md" -> "text/markdown"
    "srt" -> "application/x-subrip"
    "vtt" -> "text/vtt"
    else -> "text/plain"
}

private fun prepare(model: DetailModel, choice: ExportChoice, options: ExportOptions, folder: File): File {
    folder.mkdirs()
    val title = model.recording?.title ?: ""
    fun target(extension: String) = File(folder, ExportFileName.safe(title, extension))
    return when (choice) {
        ExportChoice.Audio -> target("m4a").also { model.audioFile.copyTo(it, overwrite = true) }
        is ExportChoice.Transcript -> target(choice.format.fileExtension).also { it.writeText(model.exportedTranscript(choice.format, options)) }
        ExportChoice.SummaryMarkdown -> target("md").also { it.writeText(model.exportedSummary()) }
        ExportChoice.SummaryPdf -> target("pdf").also { SummaryPdf.render(model.exportedSummary(), it) }
    }
}

/** Lays text out on A4 pages, as SummaryPDF in ExportSheet.swift. The system text stack handles Japanese and page breaks. */
object SummaryPdf {
    private const val WIDTH = 595
    private const val HEIGHT = 842
    private const val MARGIN = 48

    fun render(markdown: String, output: File) {
        val text = SpannableStringBuilder()
        for (line in markdown.split("\n")) {
            val (body, size, bold) = when {
                line.startsWith("## ") -> Triple(line.drop(3), 15, true)
                line.startsWith("# ") -> Triple(line.drop(2), 20, true)
                else -> Triple(line, 12, false)
            }
            val start = text.length
            text.append(body).append("\n")
            text.setSpan(AbsoluteSizeSpan(size), start, text.length, 0)
            if (bold) text.setSpan(StyleSpan(Typeface.BOLD), start, text.length, 0)
        }
        val paint = TextPaint().apply { isAntiAlias = true; textSize = 12f }
        val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, WIDTH - MARGIN * 2).setAlignment(Layout.Alignment.ALIGN_NORMAL).build()
        val document = PdfDocument()
        val printable = HEIGHT - MARGIN * 2
        var top = 0
        var pageNumber = 1
        while (top < layout.height) {
            // A page ends at the last whole line that fits.
            val lastLine = layout.getLineForVertical(top + printable)
            val bottom = if (layout.getLineBottom(lastLine) > top + printable && lastLine > layout.getLineForVertical(top)) layout.getLineTop(lastLine) else layout.getLineBottom(lastLine)
            val page = document.startPage(PdfDocument.PageInfo.Builder(WIDTH, HEIGHT, pageNumber++).create())
            page.canvas.save()
            page.canvas.translate(MARGIN.toFloat(), (MARGIN - top).toFloat())
            page.canvas.clipRect(0, top, WIDTH - MARGIN * 2, bottom)
            layout.draw(page.canvas)
            page.canvas.restore()
            document.finishPage(page)
            top = maxOf(bottom, top + 1)
        }
        output.outputStream().use { document.writeTo(it) }
        document.close()
    }
}
