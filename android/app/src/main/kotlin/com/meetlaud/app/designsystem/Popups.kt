package com.meetlaud.app.designsystem

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties

/** One choice in a menu. `isChecked` draws the checkmark iOS shows next to the current choice in a picker. */
data class MenuAction(
    val title: String,
    val symbol: String? = null,
    val isDestructive: Boolean = false,
    val isChecked: Boolean = false,
    val isEnabled: Boolean = true,
    val tag: String? = null,
    val onClick: () -> Unit,
)

/** A divider between groups of a menu. */
val MenuDivider = MenuAction("—") {}

/** Places a menu under its button, kept inside the screen, the way UIMenu opens from a bar button. */
/**
 * Where an iOS 26 menu opens: over the button it grows from, its edge on the button's edge, so the button seems to
 * become the menu. Near the bottom of the screen it grows upward from the button instead. `inset` is the padding
 * around the panel, which must not count as distance.
 */
private class MenuPosition(private val margin: Int, private val inset: Int) : PopupPositionProvider {
    override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
        val alignRight = anchorBounds.center.x > windowSize.width / 2
        val x = if (alignRight) anchorBounds.right - popupContentSize.width + inset else anchorBounds.left - inset
        val down = anchorBounds.top - inset
        val y = if (down + popupContentSize.height <= windowSize.height - margin) down else anchorBounds.bottom + inset - popupContentSize.height
        val maxX = maxOf(0, windowSize.width - popupContentSize.width)
        return IntOffset(x.coerceIn(0, maxX), y.coerceAtLeast(0))
    }
}

/**
 * A menu as iOS 26 draws one: a glass panel with rounded corners, a row per action with its symbol in front, and
 * thin dividers between groups.
 */
@Composable
fun IosMenu(expanded: Boolean, onDismiss: () -> Unit, actions: List<MenuAction>, title: String? = null) {
    if (!expanded) return
    val isDark = LocalDarkTheme.current
    val density = androidx.compose.ui.platform.LocalDensity.current
    val margin = with(density) { 12.dp.roundToPx() }
    val inset = with(density) { Spacing.small.roundToPx() }
    Popup(popupPositionProvider = MenuPosition(margin, inset), onDismissRequest = onDismiss, properties = PopupProperties(focusable = true)) {
        var shown by remember { mutableStateOf(false) }
        LaunchedEffect(Unit) { shown = true }
        AnimatedVisibility(shown, enter = fadeIn(tween(140)) + androidx.compose.animation.scaleIn(tween(160), initialScale = 0.92f)) {
            Column(
                Modifier
                    .padding(Spacing.small)
                    .widthIn(min = 250.dp, max = 290.dp)
                    .width(IntrinsicSize.Max)
                    .glass(RoundedCornerShape(24.dp), isDark, elevation = 24.dp)
                    .clip(RoundedCornerShape(24.dp))
                    .padding(vertical = Spacing.small),
            ) {
                if (title != null) {
                    Text(title, style = DsType.note, color = Ds.secondaryText.value, modifier = Modifier.padding(horizontal = Spacing.medium + 4.dp, vertical = Spacing.small))
                }
                for (action in actions) {
                    if (action === MenuDivider) {
                        HorizontalDivider(Modifier.padding(vertical = Spacing.xSmall), thickness = 0.5.dp, color = Ds.separator.value)
                        continue
                    }
                    val color = when {
                        !action.isEnabled -> Ds.secondaryText.value
                        action.isDestructive -> Ds.record.value
                        else -> Ds.primaryText.value
                    }
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(min = 42.dp)
                            .clickable(remember { MutableInteractionSource() }, indication = null, enabled = action.isEnabled) {
                                onDismiss()
                                action.onClick()
                            }
                            .then(if (action.tag != null) Modifier.testTag(action.tag) else Modifier)
                            .padding(horizontal = Spacing.medium + 4.dp, vertical = Spacing.small),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.width(28.dp)) {
                            when {
                                action.isChecked -> SfIcon("checkmark", tint = color)
                                action.symbol != null -> SfIcon(action.symbol, tint = color)
                            }
                        }
                        Spacer(Modifier.width(Spacing.small))
                        Text(action.title, style = DsType.rowTitle, color = color)
                    }
                }
            }
        }
    }
}

internal fun Modifier.testTagSafe(tag: String): Modifier = this.then(Modifier.testTag(tag))

/** A button in an alert. Cancel is bold, as on iOS, and destructive is red. */
data class AlertButton(val title: String, val role: Role = Role.DEFAULT, val tag: String? = null, val onClick: () -> Unit = {}) {
    enum class Role { DEFAULT, CANCEL, DESTRUCTIVE }
}

/**
 * An alert as iOS draws one: centered title and message on a rounded panel, buttons below, side by side when there
 * are two, stacked otherwise. `field` adds a text field, as `.alert` with a TextField does.
 */
@Composable
fun IosAlert(
    title: String,
    message: String? = null,
    buttons: List<AlertButton>,
    onDismiss: () -> Unit,
    field: (@Composable () -> Unit)? = null,
) {
    val isDark = LocalDarkTheme.current
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            Modifier
                .width(300.dp)
                .clip(RoundedCornerShape(28.dp))
                .background(if (isDark) Color(0xFF2C2C2E) else Color(0xFFF7F7F7))
                .imePadding(),
        ) {
            Column(Modifier.padding(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(title, style = DsType.heading, color = Ds.primaryText.value, textAlign = TextAlign.Center)
                if (message != null) {
                    Spacer(Modifier.height(Spacing.xSmall))
                    Text(message, style = DsType.note, color = Ds.primaryText.value, textAlign = TextAlign.Center)
                }
                if (field != null) {
                    Spacer(Modifier.height(Spacing.compact))
                    field()
                }
            }
            val sideBySide = buttons.size == 2
            if (sideBySide) {
                Row(Modifier.fillMaxWidth().padding(start = Spacing.compact, end = Spacing.compact, bottom = Spacing.compact), horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
                    // Cancel goes on the left, as iOS places it.
                    buttons.sortedBy { if (it.role == AlertButton.Role.CANCEL) 0 else 1 }.forEach { AlertCapsule(it, Modifier.weight(1f), onDismiss) }
                }
            } else {
                Column(Modifier.fillMaxWidth().padding(start = Spacing.compact, end = Spacing.compact, bottom = Spacing.compact), verticalArrangement = Arrangement.spacedBy(Spacing.small)) {
                    buttons.sortedBy { if (it.role == AlertButton.Role.CANCEL) 1 else 0 }.forEach { AlertCapsule(it, Modifier.fillMaxWidth(), onDismiss) }
                }
            }
        }
    }
}

/** iOS 26 alert buttons are capsules: the main one filled, the others gray. */
@Composable
private fun AlertCapsule(button: AlertButton, modifier: Modifier, onDismiss: () -> Unit) {
    val isDark = LocalDarkTheme.current
    val color = when (button.role) {
        AlertButton.Role.DESTRUCTIVE -> Ds.record.value
        else -> Ds.primaryText.value
    }
    Box(
        modifier
            .heightIn(min = 48.dp)
            .clip(CircleShape)
            .background(if (isDark) Color(0xFF3A3A3C) else Color(0xFFE5E5EA))
            .clickable(remember { MutableInteractionSource() }, indication = null) {
                onDismiss()
                button.onClick()
            }
            .then(if (button.tag != null) Modifier.testTagSafe(button.tag) else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            button.title,
            style = DsType.rowTitle.copy(fontWeight = if (button.role == AlertButton.Role.CANCEL) FontWeight.Normal else FontWeight.SemiBold),
            color = color,
            modifier = Modifier.padding(horizontal = Spacing.medium, vertical = Spacing.compact),
            textAlign = TextAlign.Center,
        )
    }
}

/** A list of choices from the bottom, as `.confirmationDialog` shows on a phone. */
@Composable
fun IosActionSheet(title: String?, message: String? = null, actions: List<AlertButton>, onDismiss: () -> Unit) {
    val isDark = LocalDarkTheme.current
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().clickable(remember { MutableInteractionSource() }, indication = null, onClick = onDismiss), contentAlignment = Alignment.BottomCenter) {
            Column(
                Modifier
                    .navigationBarsPadding()
                    .padding(Spacing.small)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(30.dp))
                    .background(if (isDark) Color(0xFF2C2C2E) else Color(0xFFF7F7F7))
                    .clickable(remember { MutableInteractionSource() }, indication = null) {}
                    .padding(Spacing.compact),
                verticalArrangement = Arrangement.spacedBy(Spacing.small),
            ) {
                if (title != null || message != null) {
                    Column(Modifier.fillMaxWidth().padding(Spacing.small), horizontalAlignment = Alignment.CenterHorizontally) {
                        if (title != null) Text(title, style = DsType.note.copy(fontWeight = FontWeight.SemiBold), color = Ds.secondaryText.value, textAlign = TextAlign.Center)
                        if (message != null) Text(message, style = DsType.note, color = Ds.secondaryText.value, textAlign = TextAlign.Center)
                    }
                }
                actions.sortedBy { if (it.role == AlertButton.Role.CANCEL) 1 else 0 }.forEach { AlertCapsule(it, Modifier.fillMaxWidth(), onDismiss) }
            }
        }
    }
}

/**
 * A sheet as iOS 26 shows one: it rises from the bottom over a dimmed screen, with large rounded corners, and a
 * swipe down or Back closes it. `large` fills most of the screen; otherwise it takes the height of its content.
 */
@Composable
fun IosSheet(onDismiss: () -> Unit, large: Boolean = true, content: @Composable ColumnScope.() -> Unit) {
    val isDark = LocalDarkTheme.current
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        var shown by remember { mutableStateOf(false) }
        LaunchedEffect(Unit) { shown = true }
        BackHandler(onBack = onDismiss)
        Box(Modifier.fillMaxSize().clickable(remember { MutableInteractionSource() }, indication = null, onClick = onDismiss), contentAlignment = Alignment.BottomCenter) {
            AnimatedVisibility(shown, enter = slideInVertically(tween(320)) { it }, exit = slideOutVertically(tween(250)) { it } + fadeOut()) {
                Column(
                    Modifier
                        .statusBarsPadding()
                        .padding(top = if (large) 10.dp else 0.dp)
                        .padding(horizontal = if (large) 0.dp else 8.dp)
                        .fillMaxWidth()
                        .then(if (large) Modifier.fillMaxHeight() else Modifier)
                        .clip(RoundedCornerShape(topStart = 38.dp, topEnd = 38.dp, bottomStart = if (large) 0.dp else 38.dp, bottomEnd = if (large) 0.dp else 38.dp))
                        .background(if (isDark) Color(0xFF1C1C1E) else Ds.background.value)
                        .clickable(remember { MutableInteractionSource() }, indication = null) {}
                        .navigationBarsPadding()
                        .imePadding(),
                    content = content,
                )
            }
        }
    }
}

/** The bar at the top of a sheet: a round button at each side and the title between, as in a sheet's toolbar. */
@Composable
fun SheetBar(title: String?, leading: (@Composable () -> Unit)? = null, trailing: (@Composable () -> Unit)? = null) {
    Box(Modifier.fillMaxWidth().padding(horizontal = Spacing.medium).padding(top = Spacing.medium).height(52.dp)) {
        Box(Modifier.align(Alignment.CenterStart)) { leading?.invoke() }
        if (title != null) {
            Text(title, style = DsType.navTitle, color = Ds.primaryText.value, modifier = Modifier.align(Alignment.Center).padding(horizontal = 64.dp), maxLines = 1)
        }
        Box(Modifier.align(Alignment.CenterEnd)) { trailing?.invoke() }
    }
}

/** A scrolling column for the body of a sheet. */
@Composable
fun SheetBody(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.verticalScroll(rememberScrollState()).padding(bottom = Spacing.large), content = content)
}

