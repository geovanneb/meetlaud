package com.meetlaud.app.designsystem

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
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
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/** One option in a ChoiceSheet. */
data class Choice<T>(val value: T, val title: String, val symbol: String? = null, val identifier: String? = null)

/** A large title and a round close button, at the top of a sheet that is only as tall as its content. */
@Composable
fun SheetHeader(title: String, closeLabel: String, onClose: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = DsType.pageTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f).semantics { heading() })
        Spacer(Modifier.width(Spacing.small))
        GlassCircleButton("xmark", closeLabel, Modifier.testTag("choice.close"), iconSize = 18.dp, onClick = onClose)
    }
}

/** A short list of options in a sheet from the bottom, only as tall as its content, as ChoiceSheet.swift. */
@Composable
fun <T> ChoiceSheet(title: String, closeLabel: String, choices: List<Choice<T>>, selection: T, onSelect: (T) -> Unit, onDismiss: () -> Unit) {
    IosSheet(onDismiss, large = false) {
        SheetBody(Modifier.padding(Spacing.large)) {
            SheetHeader(title, closeLabel, onDismiss)
            Spacer(Modifier.height(Spacing.small))
            for (choice in choices) {
                val isSelected = choice.value == selection
                PlainButton(
                    {
                        onSelect(choice.value)
                        onDismiss()
                    },
                    Modifier.fillMaxWidth().heightIn(min = TapTarget).semantics { selected = isSelected }.then(if (choice.identifier != null) Modifier.testTag(choice.identifier) else Modifier),
                ) {
                    if (choice.symbol != null) {
                        SfIcon(choice.symbol, Modifier.width(Spacing.large))
                        Spacer(Modifier.width(Spacing.compact))
                    }
                    Text(choice.title, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f))
                    if (isSelected) SfIcon("checkmark", tint = Ds.action.value)
                }
            }
        }
    }
}

/** A row that opens something: an icon, a title, the current value, and a chevron. */
@Composable
fun SettingsRowLabel(title: String, modifier: Modifier = Modifier, symbol: String? = null, value: String? = null) {
    Row(modifier.fillMaxWidth().heightIn(min = TapTarget), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.medium)) {
        if (symbol != null) SfIcon(symbol, Modifier.width(Spacing.large), tint = Ds.secondaryText.value)
        Text(title, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f))
        if (value != null) Text(value, style = DsType.rowTitle, color = Ds.secondaryText.value)
        SfIcon("chevron.right", tint = Ds.secondaryText.value, size = DsType.note.fontSize)
    }
}

/** An action revealed by swiping a row, as `.swipeActions`. */
data class SwipeAction(val title: String, val symbol: String, val tint: Color, val onClick: () -> Unit)

/**
 * A row with swipe actions on either side, as iOS lists have. A full swipe runs the first action of that side, the
 * way iOS does for a destructive one. TalkBack reaches the same actions as custom actions.
 */
@Composable
fun SwipeRow(
    modifier: Modifier = Modifier,
    leading: List<SwipeAction> = emptyList(),
    trailing: List<SwipeAction> = emptyList(),
    content: @Composable () -> Unit,
) {
    val density = LocalDensity.current
    val button = with(density) { 74.dp.toPx() }
    val offset = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    var width by remember { mutableStateOf(0f) }
    val haptics = LocalHapticFeedback.current
    fun close() = scope.launch { offset.animateTo(0f, tween(220)) }
    val leadingWidth = button * leading.size
    val trailingWidth = button * trailing.size

    Box(
        modifier
            .fillMaxWidth()
            .onSizeChanged { width = it.width.toFloat() }
            .semantics {
                customActions = (leading + trailing).map { CustomAccessibilityAction(it.title) { it.onClick(); true } }
            },
    ) {
        if (offset.value > 0 && leading.isNotEmpty()) {
            Row(Modifier.matchParentSize()) {
                leading.forEach { action -> SwipeButton(action, Modifier.width(with(density) { (offset.value / leading.size).toDp() })) { close(); action.onClick() } }
            }
        }
        if (offset.value < 0 && trailing.isNotEmpty()) {
            Row(Modifier.matchParentSize(), horizontalArrangement = Arrangement.End) {
                trailing.reversed().forEach { action -> SwipeButton(action, Modifier.width(with(density) { (-offset.value / trailing.size).toDp() })) { close(); action.onClick() } }
            }
        }
        Box(
            Modifier
                .offset { IntOffset(offset.value.roundToInt(), 0) }
                .background(Ds.background.value)
                .draggable(
                    rememberDraggableState { delta ->
                        val next = (offset.value + delta).coerceIn(if (trailing.isEmpty()) 0f else -width, if (leading.isEmpty()) 0f else width)
                        scope.launch { offset.snapTo(next) }
                    },
                    Orientation.Horizontal,
                    onDragStopped = {
                        val value = offset.value
                        val target = when {
                            value < -width * 0.6f && trailing.isNotEmpty() -> {
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                trailing.first().onClick()
                                0f
                            }
                            value > width * 0.6f && leading.isNotEmpty() -> {
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                leading.first().onClick()
                                0f
                            }
                            value < -trailingWidth / 2 -> -trailingWidth
                            value > leadingWidth / 2 -> leadingWidth
                            else -> 0f
                        }
                        offset.animateTo(target, tween(220))
                    },
                ),
        ) { content() }
    }
}

@Composable
private fun SwipeButton(action: SwipeAction, modifier: Modifier, onClick: () -> Unit) {
    Column(
        modifier.fillMaxHeight().background(action.tint).clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        SfIcon(action.symbol, tint = Color.White)
        Text(action.title, style = DsType.badge, color = Color.White, maxLines = 1)
    }
}

/**
 * A row that opens a menu when pressed and held, as `.contextMenu`. A tap still runs `onClick`. The row lifts on a
 * surface while its menu is open, as iOS shows the item a menu is about.
 */
@Composable
fun ContextMenuRow(actions: List<MenuAction>, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable () -> Unit) {
    var open by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    Box(modifier) {
        Box(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(Radius.medium))
                .background(if (open) Ds.surface.value else Color.Transparent)
                .combinedClickable(
                    remember { MutableInteractionSource() }, indication = null, enabled = enabled, role = Role.Button,
                    onLongClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        open = true
                    },
                    onClick = onClick,
                ),
        ) { content() }
        IosMenu(open, { open = false }, actions)
    }
}

/** The search field of `.searchable`: a rounded gray capsule with a magnifying glass, focused when it appears. */
@Composable
fun SearchField(query: String, onQuery: (String) -> Unit, prompt: String, modifier: Modifier = Modifier, focus: Boolean = true) {
    val requester = remember { FocusRequester() }
    LaunchedEffect(Unit) { if (focus) requester.requestFocus() }
    Row(
        modifier
            .fillMaxWidth()
            .height(48.dp)
            .glass(CircleShape, LocalDarkTheme.current)
            .clip(CircleShape)
            .padding(horizontal = Spacing.medium),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.small),
    ) {
        SfIcon("magnifyingglass", tint = Ds.secondaryText.value)
        Box(Modifier.weight(1f)) {
            if (query.isEmpty()) Text(prompt, style = DsType.rowTitle, color = Ds.secondaryText.value)
            BasicTextField(
                query, onQuery,
                Modifier.fillMaxWidth().focusRequester(requester).testTag("search.field"),
                textStyle = DsType.rowTitle.copy(color = Ds.primaryText.value),
                singleLine = true,
                cursorBrush = SolidColor(Ds.action.value),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(),
            )
        }
        if (query.isNotEmpty()) {
            PlainButton({ onQuery("") }, Modifier.size(28.dp)) {
                Box(Modifier.size(18.dp).clip(CircleShape).background(Ds.secondaryText.value), contentAlignment = Alignment.Center) {
                    SfIcon("xmark", 11.dp, tint = Ds.background.value)
                }
            }
        }
    }
}


/**
 * A section of the standard grouped list, as `.screenList()` draws it: a title, rows flat on the page with hairlines
 * between them, and a note under the last row. Settings and most screens use this; forms in sheets use FormSection.
 */
@Composable
fun ListSection(header: String? = null, footer: String? = null, modifier: Modifier = Modifier, content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().padding(bottom = Spacing.medium)) {
        if (header != null) SectionHeader(header)
        content()
        if (footer != null) {
            Text(footer, style = DsType.note, color = Ds.secondaryText.value, modifier = Modifier.padding(horizontal = Spacing.medium, vertical = Spacing.small))
        }
    }
}

/** A row of a ListSection: tappable or not, at least a tap target tall, with the hairline under it. */
@Composable
fun ListRow(modifier: Modifier = Modifier, divider: Boolean = true, onClick: (() -> Unit)? = null, content: @Composable () -> Unit) {
    Column {
        Box(
            modifier
                .fillMaxWidth()
                .heightIn(min = TapTarget + 8.dp)
                .then(if (onClick != null) Modifier.clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClick = onClick) else Modifier)
                .padding(horizontal = Spacing.medium, vertical = Spacing.small),
            contentAlignment = Alignment.CenterStart,
        ) { content() }
        if (divider) RowDivider(Modifier.padding(horizontal = Spacing.medium))
    }
}

/** A switch row of a ListSection, as Toggle in a list. */
@Composable
fun ListToggle(title: String, isOn: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, divider: Boolean = true) {
    ListRow(modifier, divider, if (enabled) ({ onChange(!isOn) }) else null) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = DsType.rowTitle, color = if (enabled) Ds.primaryText.value else Ds.secondaryText.value, modifier = Modifier.weight(1f))
            Spacer(Modifier.width(Spacing.compact))
            IosSwitch(isOn, onChange, enabled = enabled)
        }
    }
}
