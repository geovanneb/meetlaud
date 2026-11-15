package com.meetlaud.app.designsystem

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// The app's feedback vocabulary, as Feedback.swift (D-079). A known fraction gets a bar or a ring that fills. An
// unknown one gets motion that never stops. Reduced motion turns movement into a gentle pulse of opacity.

/** A small ring that fills to a fraction, or spins when the fraction is unknown. */
@Composable
fun ProgressRing(fraction: Double?, modifier: Modifier = Modifier, tint: Color = Ds.action.value) {
    // 20 points at the default text size, growing with it as @ScaledMetric does.
    val size = with(LocalDensity.current) { 20.sp.toDp() }
    val track = Ds.track.value
    val reduceMotion = LocalReduceMotion.current
    val turning = rememberInfiniteTransition(label = "ring")
    val angle by turning.animateFloat(0f, 360f, infiniteRepeatable(tween(900, easing = LinearEasing)), label = "angle")
    val pulse by turning.animateFloat(0.3f, 0.9f, infiniteRepeatable(tween(1000), RepeatMode.Reverse), label = "pulse")
    val shown by animateFloatAsState((fraction ?: 0.0).coerceIn(0.0, 1.0).toFloat(), Motion.standard(), label = "fraction")
    Canvas(modifier.size(size).clearAndSetSemantics {}) {
        val width = maxOf(2.dp.toPx(), this.size.width / 8)
        val inset = width / 2
        val arcSize = androidx.compose.ui.geometry.Size(this.size.width - width, this.size.height - width)
        val topLeft = androidx.compose.ui.geometry.Offset(inset, inset)
        drawArc(track, 0f, 360f, false, topLeft, arcSize, style = Stroke(width))
        when {
            fraction != null -> drawArc(tint, -90f, 360f * maxOf(shown, 0.02f), false, topLeft, arcSize, style = Stroke(width, cap = StrokeCap.Round))
            reduceMotion -> drawArc(tint.copy(alpha = pulse), 0f, 360f, false, topLeft, arcSize, style = Stroke(width))
            else -> drawArc(tint, angle - 90f, 108f, false, topLeft, arcSize, style = Stroke(width, cap = StrokeCap.Round))
        }
    }
}

/** A thin bar. With a fraction it fills. Without one, a light sweeps across it, so work is never mistaken for stuck. */
@Composable
fun ActivityBar(fraction: Double?, modifier: Modifier = Modifier, tint: Color = Ds.action.value) {
    val reduceMotion = LocalReduceMotion.current
    val sweep = rememberInfiniteTransition(label = "bar")
    val position by sweep.animateFloat(-0.3f, 1f, infiniteRepeatable(tween(1300)), label = "sweep")
    val pulse by sweep.animateFloat(0.2f, 0.7f, infiniteRepeatable(tween(1000), RepeatMode.Reverse), label = "pulse")
    val shown by animateFloatAsState((fraction ?: 0.0).coerceIn(0.0, 1.0).toFloat(), Motion.standard(), label = "fraction")
    BoxWithConstraints(modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(Ds.track.value).clearAndSetSemantics {}) {
        when {
            fraction != null -> Box(Modifier.fillMaxHeight().width(maxOf(6.dp, maxWidth * shown)).clip(CircleShape).background(tint))
            reduceMotion -> Box(Modifier.fillMaxHeight().fillMaxWidth().alpha(pulse).background(tint))
            else -> Box(Modifier.fillMaxHeight().width(maxWidth * 0.3f).offset(x = maxWidth * position).clip(CircleShape).background(tint))
        }
    }
}

/** One step of a longer piece of work. */
data class ProcessStep(val id: String, val title: String, val state: State) {
    enum class State { WAITING, ACTIVE, DONE }
}

/** What TalkBack says for each state. Passed in, since text lives in the String Catalog. */
data class ProcessStepLabels(val waiting: String, val active: String, val done: String)

/** The steps of a piece of work, in order: done ones checked, the current one turning, the rest waiting. */
@Composable
fun StepList(steps: List<ProcessStep>, labels: ProcessStepLabels, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.small)) {
        for (step in steps) {
            Row(
                Modifier.semantics(mergeDescendants = true) {
                    contentDescription = step.title
                    stateDescription = when (step.state) {
                        ProcessStep.State.WAITING -> labels.waiting
                        ProcessStep.State.ACTIVE -> labels.active
                        ProcessStep.State.DONE -> labels.done
                    }
                },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.small),
            ) {
                Box(Modifier.widthIn(min = Spacing.large), contentAlignment = Alignment.Center) {
                    when (step.state) {
                        ProcessStep.State.DONE -> FilledCheck(Ds.positive.value)
                        ProcessStep.State.ACTIVE -> ProgressRing(null)
                        ProcessStep.State.WAITING -> SfIcon("circle.dashed", tint = Ds.secondaryText.value, size = DsType.meta.fontSize)
                    }
                }
                Text(
                    step.title,
                    style = DsType.meta.copy(fontWeight = if (step.state == ProcessStep.State.ACTIVE) FontWeight.SemiBold else FontWeight.Normal),
                    color = if (step.state == ProcessStep.State.WAITING) Ds.secondaryText.value else Ds.primaryText.value,
                )
            }
        }
    }
}

/** checkmark.circle.fill: a filled circle with the check cut out in the background color. */
@Composable
fun FilledCheck(tint: Color, size: Dp = with(LocalDensity.current) { DsType.meta.fontSize.toDp() } * 1.18f) {
    Box(Modifier.size(size).clip(CircleShape).background(tint), contentAlignment = Alignment.Center) {
        SfIcon("checkmark", size * 0.7f, tint = Ds.background.value)
    }
}

/** A short state next to a title. A symbol or a ring always goes with the words, never color alone. */
@Composable
fun StatusBadge(text: String, tone: Tone, modifier: Modifier = Modifier, fraction: Double? = null, symbol: String? = null) {
    val color = when (tone) {
        Tone.WORKING -> Ds.action.value
        Tone.WAITING -> Ds.secondaryText.value
        Tone.ATTENTION -> Ds.attention.value
        Tone.DONE -> Ds.positive.value
    }
    Row(
        modifier
            .clip(CircleShape)
            .background(Ds.selection.value.copy(alpha = 0.7f))
            .padding(vertical = Spacing.xSmall / 2, horizontal = Spacing.small)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.xSmall),
    ) {
        if (tone == Tone.WORKING) {
            ProgressRing(fraction, Modifier.scale(0.8f), tint = color)
        } else if (symbol != null) {
            SfIcon(symbol, tint = color, size = DsType.note.fontSize)
        }
        Text(text, style = DsType.note, color = if (tone == Tone.ATTENTION) color else Ds.primaryText.value)
    }
}

enum class Tone { WORKING, WAITING, ATTENTION, DONE }

/** One part of a whole, such as what recordings take on the device. */
data class UsagePart(val id: String, val title: String, val value: Long, val formatted: String)

/** A bar split into parts, with a legend under it, as iPhone Storage draws it. */
@Composable
fun UsageBar(parts: List<UsagePart>, modifier: Modifier = Modifier, total: Long? = null, showsLegend: Boolean = true) {
    val whole = maxOf(total ?: parts.sumOf { it.value }, 1)
    val colors = Ds.series.map { it.value }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.compact)) {
        BoxWithConstraints(Modifier.fillMaxWidth().height(12.dp).clip(RoundedCornerShape(Radius.small / 2)).background(Ds.track.value).clearAndSetSemantics {}) {
            val width = maxWidth
            Row(horizontalArrangement = Arrangement.spacedBy(1.dp)) {
                parts.forEachIndexed { index, part ->
                    if (part.value > 0) {
                        Box(Modifier.fillMaxHeight().width(maxOf(2.dp, width * (part.value.toFloat() / whole))).background(colors[index % colors.size]))
                    }
                }
            }
        }
        if (showsLegend) {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.small)) {
                parts.forEachIndexed { index, part ->
                    Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
                        UsageDot(index)
                        Text(part.title, style = DsType.meta, color = Ds.primaryText.value)
                        Spacer(Modifier.weight(1f))
                        Text(part.formatted, style = DsType.meta.copy(fontFeatureSettings = "tnum"), color = Ds.secondaryText.value)
                    }
                }
            }
        }
    }
}

/** The small swatch that ties a row to its part of a UsageBar. */
@Composable
fun UsageDot(index: Int) {
    val size = with(LocalDensity.current) { 10.sp.toDp() }
    Box(Modifier.size(size).clip(CircleShape).background(Ds.series[index % Ds.series.size].value).clearAndSetSemantics {})
}

