package com.meetlaud.app.designsystem

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * iOS 26's glass: in Light a white surface with a wide, soft shadow, in Dark a lifted gray. Buttons that float over
 * content use it: the menu and back buttons, the Record pill, the prompt bar, the recording controls.
 */
fun Modifier.glass(shape: Shape, isDark: Boolean, elevation: Dp = 18.dp): Modifier =
    this
        .shadow(elevation, shape, clip = false, ambientColor = Color.Black.copy(alpha = 0.10f), spotColor = Color.Black.copy(alpha = 0.10f))
        .background(if (isDark) Color(0xFF2A2A2D) else Color.White, shape)

/** Whether a press is down, for the dimming iOS gives every button. */
@Composable
private fun pressedAlpha(source: MutableInteractionSource): Float {
    val pressed by source.collectIsPressedAsState()
    return if (pressed) 0.55f else 1f
}

/** A round glass button with one symbol, 44 points across: menu, back, more, and the recording controls. */
@Composable
fun GlassCircleButton(
    symbol: String,
    label: String,
    modifier: Modifier = Modifier,
    diameter: Dp = TapTarget,
    tint: Color = Ds.primaryText.value,
    iconSize: Dp = 22.dp,
    onClick: () -> Unit,
) {
    val source = remember { MutableInteractionSource() }
    Box(
        modifier
            .size(diameter)
            .glass(CircleShape, LocalDarkTheme.current)
            .clip(CircleShape)
            .clickable(source, indication = null, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        SfIcon(symbol, iconSize, Modifier.alpha(pressedAlpha(source)), tint = tint)
    }
}

/** A glass capsule holding several items, such as Record and the add button on Home. */
@Composable
fun GlassCapsule(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(
        modifier
            .height(TapTarget)
            .glass(CircleShape, LocalDarkTheme.current)
            .clip(CircleShape),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

/** A plain button: the label dims while pressed, with no ripple, as on iOS. */
@Composable
fun PlainButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    label: String? = null,
    content: @Composable RowScope.() -> Unit,
) {
    val source = remember { MutableInteractionSource() }
    Row(
        modifier
            .clickable(source, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .then(if (label != null) Modifier.semantics { contentDescription = label } else Modifier)
            .alpha(if (enabled) pressedAlpha(source) else 0.4f),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

/** A text button in the action color, as a borderless iOS button. */
@Composable
fun TextAction(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, color: Color = Ds.action.value, style: TextStyle = DsType.rowTitle, onClick: () -> Unit) {
    PlainButton(onClick, modifier.defaultMinSize(minHeight = TapTarget), enabled) {
        Text(text, style = style, color = color)
    }
}

enum class ControlSize { SMALL, REGULAR, LARGE }

/** The main action of a screen. A screen has one at most. */
@Composable
fun PrimaryAction(
    text: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    symbol: String? = null,
    onClick: () -> Unit,
) {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    Row(
        modifier
            .defaultMinSize(minHeight = 50.dp)
            .clip(CircleShape)
            .background(Ds.action.value.copy(alpha = if (!enabled) 0.35f else if (pressed) 0.8f else 1f))
            .clickable(source, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        if (symbol != null) {
            SfIcon(symbol, tint = Ds.onAction.value)
            Spacer(Modifier.size(Spacing.small))
        }
        Text(text, style = DsType.rowTitle.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = Ds.onAction.value)
    }
}

/** An action that stands on its own without competing with the primary one: a solid outlined capsule. */
@Composable
fun SecondaryAction(
    text: String,
    modifier: Modifier = Modifier,
    size: ControlSize = ControlSize.LARGE,
    enabled: Boolean = true,
    symbol: String? = null,
    onClick: () -> Unit,
) {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val padding = when (size) {
        ControlSize.LARGE -> PaddingValues(horizontal = Spacing.large, vertical = Spacing.compact)
        ControlSize.REGULAR -> PaddingValues(horizontal = Spacing.medium, vertical = Spacing.small)
        ControlSize.SMALL -> PaddingValues(horizontal = Spacing.compact, vertical = Spacing.xSmall)
    }
    val color = if (enabled) Ds.primaryText.value else Ds.secondaryText.value
    Row(
        modifier
            .defaultMinSize(minHeight = TapTarget)
            .clip(CircleShape)
            .background(if (pressed) Ds.selection.value else Ds.surface.value)
            .border(BorderStroke(1.dp, Ds.selection.value), CircleShape)
            .clickable(source, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(padding),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        val style = if (size == ControlSize.LARGE) DsType.rowTitle else DsType.meta
        if (symbol != null) {
            SfIcon(symbol, tint = color, size = style.fontSize)
            Spacer(Modifier.size(Spacing.small))
        }
        Text(text, style = style, color = color)
    }
}

/** A title with a line of detail under it. The shape of almost every row in the app. */
@Composable
fun RowLabel(title: String, detail: String, modifier: Modifier = Modifier, titleLines: Int = Int.MAX_VALUE) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
        Text(title, style = DsType.rowTitle, color = Ds.primaryText.value, maxLines = titleLines, overflow = TextOverflow.Ellipsis)
        Text(detail, style = DsType.meta, color = Ds.secondaryText.value)
    }
}

/** Centered empty state. */
@Composable
fun EmptyState(title: String, message: String, symbol: String, modifier: Modifier = Modifier, inline: Boolean = false) {
    val content = @Composable {
        Column(
            Modifier.fillMaxWidth().padding(Spacing.large),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Spacing.small),
        ) {
            SfIcon(symbol, Modifier.padding(bottom = Spacing.small), tint = Ds.secondaryText.value, size = IconSize.hero)
            Text(title, style = DsType.sectionTitle, color = Ds.primaryText.value, textAlign = TextAlign.Center, modifier = Modifier.semantics { heading() })
            Text(message, style = DsType.meta, color = Ds.secondaryText.value, textAlign = TextAlign.Center)
        }
    }
    if (inline) {
        Box(modifier) { content() }
    } else {
        Box(modifier.fillMaxSize().verticalScroll(rememberScrollState()), contentAlignment = Alignment.Center) { content() }
    }
}

/** A list section title with real contrast. */
@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier) {
    Text(
        title,
        style = DsType.meta,
        color = Ds.secondaryText.value,
        modifier = modifier.padding(horizontal = Spacing.medium).padding(top = Spacing.medium, bottom = Spacing.small).semantics { heading() },
    )
}

/** iOS's list separator: a hairline, inset to where the text starts. */
@Composable
fun RowDivider(modifier: Modifier = Modifier, start: Dp = 0.dp) {
    HorizontalDivider(modifier.padding(start = start), thickness = 0.5.dp, color = Ds.separator.value)
}

/** A raised group on the page, for status and summaries that belong together, as `.dsCard()`. */
@Composable
fun Modifier.dsCard(): Modifier =
    fillMaxWidth()
        .clip(RoundedCornerShape(Radius.medium))
        .background(Ds.surface.value)
        .border(BorderStroke(1.dp, Ds.selection.value), RoundedCornerShape(Radius.medium))
        .padding(Spacing.medium)

/** A grouped section: rows on a rounded surface, divided by hairlines, as an inset grouped iOS list. */
@Composable
fun GroupedSection(
    modifier: Modifier = Modifier,
    header: String? = null,
    footer: String? = null,
    content: @Composable () -> Unit,
) {
    Column(modifier.fillMaxWidth().padding(horizontal = Spacing.medium)) {
        if (header != null) {
            Text(header, style = DsType.meta, color = Ds.secondaryText.value, modifier = Modifier.padding(start = Spacing.medium, bottom = Spacing.small, top = Spacing.small).semantics { heading() })
        }
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(26.dp)).background(Ds.surface.value)) { content() }
        if (footer != null) {
            Text(footer, style = DsType.note, color = Ds.secondaryText.value, modifier = Modifier.padding(horizontal = Spacing.medium, vertical = Spacing.small))
        }
    }
}
