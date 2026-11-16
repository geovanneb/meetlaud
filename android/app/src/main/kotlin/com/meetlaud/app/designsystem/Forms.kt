package com.meetlaud.app.designsystem

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp

/**
 * A section of an iOS Form: rows on a rounded surface, divided by hairlines inset to the text, with a header above
 * and a footer below.
 */
@Composable
fun FormSection(header: String? = null, footer: String? = null, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().padding(horizontal = Spacing.medium).padding(bottom = Spacing.large)) {
        if (header != null) {
            Text(header, style = DsType.meta, color = Ds.secondaryText.value, modifier = Modifier.padding(start = Spacing.medium, bottom = Spacing.small).semantics { heading() })
        }
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(26.dp)).background(Ds.surface.value), content = content)
        if (footer != null) {
            Text(footer, style = DsType.note, color = Ds.secondaryText.value, modifier = Modifier.padding(horizontal = Spacing.medium).padding(top = Spacing.small))
        }
    }
}

/** A row in a FormSection, with the hairline under it unless it is the last. */
@Composable
fun FormRow(modifier: Modifier = Modifier, divider: Boolean = true, onClick: (() -> Unit)? = null, content: @Composable () -> Unit) {
    Column {
        Box(
            modifier
                .fillMaxWidth()
                .heightIn(min = 52.dp)
                .then(if (onClick != null) Modifier.clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClick = onClick) else Modifier)
                .padding(horizontal = Spacing.medium + 4.dp, vertical = Spacing.compact),
            contentAlignment = Alignment.CenterStart,
        ) { content() }
        if (divider) RowDivider(Modifier.padding(start = Spacing.medium + 4.dp))
    }
}

/** A row that is one action, in the action color, as a Button inside a Form. */
@Composable
fun FormButton(title: String, modifier: Modifier = Modifier, destructive: Boolean = false, enabled: Boolean = true, divider: Boolean = true, symbol: String? = null, onClick: () -> Unit) {
    FormRow(modifier, divider, if (enabled) onClick else null) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            val color = when {
                !enabled -> Ds.secondaryText.value
                destructive -> Ds.record.value
                else -> Ds.action.value
            }
            if (symbol != null) {
                SfIcon(symbol, Modifier.width(Spacing.large), tint = color)
                Spacer(Modifier.width(Spacing.compact))
            }
            Text(title, style = DsType.rowTitle, color = color)
        }
    }
}

/** A text field filling a Form row, as TextField inside a Form. */
@Composable
fun FormTextField(value: String, onValue: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, divider: Boolean = true, singleLine: Boolean = true) {
    FormRow(modifier, divider) {
        Box(Modifier.fillMaxWidth()) {
            if (value.isEmpty()) Text(placeholder, style = DsType.rowTitle, color = Ds.secondaryText.value)
            BasicTextField(
                value, onValue, Modifier.fillMaxWidth(),
                textStyle = DsType.rowTitle.copy(color = Ds.primaryText.value),
                singleLine = singleLine,
                cursorBrush = SolidColor(Ds.action.value),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            )
        }
    }
}

/** A switch row, as Toggle inside a Form. */
@Composable
fun FormToggle(title: String, isOn: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, divider: Boolean = true, symbol: String? = null, detail: String? = null) {
    FormRow(modifier, divider, if (enabled) ({ onChange(!isOn) }) else null) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (symbol != null) {
                SfIcon(symbol, Modifier.width(Spacing.large), tint = Ds.secondaryText.value)
                Spacer(Modifier.width(Spacing.compact))
            }
            Column(Modifier.weight(1f)) {
                Text(title, style = DsType.rowTitle, color = if (enabled) Ds.primaryText.value else Ds.secondaryText.value)
                if (detail != null) Text(detail, style = DsType.note, color = Ds.secondaryText.value)
            }
            Spacer(Modifier.width(Spacing.compact))
            IosSwitch(isOn, onChange, enabled = enabled)
        }
    }
}

/** The iOS switch: a green capsule with a white knob that slides. */
@Composable
fun IosSwitch(isOn: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    val track by animateColorAsState(if (isOn) Color(0xFF34C759) else Ds.track.value, Motion.quick(), label = "track")
    val knob by animateDpAsState(if (isOn) 22.dp else 2.dp, Motion.quick(), label = "knob")
    Box(
        modifier
            .size(62.dp, 28.dp)
            .clip(CircleShape)
            .background(track.copy(alpha = if (enabled) 1f else 0.5f))
            .clickable(remember { MutableInteractionSource() }, indication = null, enabled = enabled, role = Role.Switch) { onChange(!isOn) }
            .semantics { toggleableState = ToggleableState(isOn) },
    ) {
        Box(Modifier.offset(x = knob, y = 2.dp).size(38.dp, 24.dp).shadow(2.dp, CircleShape).clip(CircleShape).background(Color.White))
    }
}

/** The segmented control of a Picker: a gray capsule with a white thumb that slides to the chosen segment. */
@Composable
fun SegmentedControl(segments: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier, tags: List<String>? = null) {
    val isDark = LocalDarkTheme.current
    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .height(36.dp)
            .clip(CircleShape)
            .background(if (isDark) Color(0xFF2C2C2E) else Color(0xFFE9E9EB))
            .padding(2.dp),
    ) {
        val width = maxWidth / segments.size
        val x by animateDpAsState(width * selected, Motion.quick(), label = "thumb")
        Box(Modifier.offset(x = x).width(width).fillMaxHeight().shadow(3.dp, CircleShape).clip(CircleShape).background(if (isDark) Color(0xFF636366) else Color.White))
        Row(Modifier.fillMaxWidth().fillMaxHeight()) {
            segments.forEachIndexed { index, title ->
                Box(
                    Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Tab) { onSelect(index) }
                        .semantics { this.selected = index == selected }
                        .then(if (tags != null) Modifier.testTag(tags[index]) else Modifier),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(title, style = DsType.meta.copy(fontWeight = if (index == selected) FontWeight.SemiBold else FontWeight.Medium), color = Ds.primaryText.value, maxLines = 1)
                }
            }
        }
    }
}

/** The iOS slider: a thin track, the filled part in the action color, a white knob with a shadow. */
@Composable
fun IosSlider(value: Double, range: ClosedFloatingPointRange<Double>, onChange: (Double) -> Unit, onFinished: () -> Unit, modifier: Modifier = Modifier, label: String, valueText: String) {
    val density = LocalDensity.current
    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .height(32.dp)
            .semantics {
                contentDescription = label
                stateDescription = valueText
                progressBarRangeInfo = ProgressBarRangeInfo(value.toFloat(), range.start.toFloat()..range.endInclusive.toFloat())
                setProgress { target ->
                    onChange(target.toDouble())
                    onFinished()
                    true
                }
            },
    ) {
        val track = maxWidth
        val widthPx = with(density) { track.toPx() }
        val knob = 28.dp
        val knobPx = with(density) { knob.toPx() }
        val span = range.endInclusive - range.start
        val fraction = if (span <= 0) 0.0 else ((value - range.start) / span).coerceIn(0.0, 1.0)
        fun valueAt(x: Float): Double = range.start + span * ((x - knobPx / 2) / (widthPx - knobPx)).coerceIn(0f, 1f)
        Box(
            Modifier
                .fillMaxWidth()
                .fillMaxHeight()
                .pointerInput(range) {
                    detectTapGestures { onChange(valueAt(it.x)); onFinished() }
                }
                .pointerInput(range) {
                    detectDragGestures(onDragEnd = onFinished, onDragCancel = onFinished) { change, _ -> onChange(valueAt(change.position.x)) }
                },
            contentAlignment = Alignment.CenterStart,
        ) {
            Box(Modifier.padding(horizontal = knob / 2).fillMaxWidth().height(4.dp).clip(CircleShape).background(Ds.track.value))
            Box(Modifier.padding(start = knob / 2).width((track - knob) * fraction.toFloat()).height(4.dp).clip(CircleShape).background(Ds.action.value))
            Box(Modifier.offset(x = (track - knob) * fraction.toFloat()).size(knob).shadow(4.dp, CircleShape).clip(CircleShape).background(Color.White))
        }
    }
}

