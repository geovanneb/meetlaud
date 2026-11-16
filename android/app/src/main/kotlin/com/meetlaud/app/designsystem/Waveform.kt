package com.meetlaud.app.designsystem

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Bars for recent audio levels, newest on the right, as WaveformView.swift. Hidden from TalkBack. */
@Composable
fun WaveformView(levels: List<Float>, isActive: Boolean, modifier: Modifier = Modifier) {
    val color = if (isActive) Ds.record.value else Ds.secondaryText.value
    Canvas(modifier.clearAndSetSemantics {}) {
        val bar = 3.dp.toPx()
        val gap = 3.dp.toPx()
        val count = (size.width / (bar + gap)).toInt()
        levels.takeLast(count).reversed().forEachIndexed { offset, level ->
            val height = maxOf(3.dp.toPx(), level * size.height)
            drawRoundRect(color, Offset(size.width - (offset + 1) * (bar + gap), (size.height - height) / 2), Size(bar, height), CornerRadius(bar / 2))
        }
    }
}

/** A round glass button of any size, with any symbol inside. */
@Composable
fun GlassCircle(label: String, diameter: Dp, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit, content: @Composable () -> Unit) {
    Box(
        modifier
            .size(diameter)
            .glass(CircleShape, LocalDarkTheme.current)
            .clip(CircleShape)
            .clickable(remember { MutableInteractionSource() }, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label }
            .alpha(if (enabled) 1f else 0.4f),
        contentAlignment = Alignment.Center,
    ) { content() }
}

