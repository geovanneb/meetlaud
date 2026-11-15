package com.meetlaud.app.shell

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.GlassCircleButton
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.localization.Strings

/** What the shell gives a screen's bar: the menu at a root, the back button above it. */
data class NavigationChrome(
    val onMenu: (() -> Unit)? = null,
    val onBack: (() -> Unit)? = null,
    /** Space the floating bars take at the bottom, so the last row can scroll clear of them. */
    val bottomInset: Dp = 0.dp,
)

val LocalNavigationChrome = compositionLocalOf { NavigationChrome() }

/**
 * The navigation bar of an iOS 26 screen: a glass button at each side, and the title centered between them in the
 * inline style. A screen with a large title shows it in its content, through [LargeTitle].
 */
@Composable
fun NavigationBar(
    title: String? = null,
    modifier: Modifier = Modifier,
    leading: (@Composable RowScope.() -> Unit)? = null,
    trailing: @Composable RowScope.() -> Unit = {},
) {
    val chrome = LocalNavigationChrome.current
    // iOS 26 centers its glass buttons 23 points below the safe area.
    Box(modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = Spacing.medium).height(46.dp)) {
        Row(Modifier.align(Alignment.CenterStart), verticalAlignment = Alignment.CenterVertically) {
            when {
                leading != null -> leading()
                chrome.onBack != null -> GlassCircleButton("chevron.left", com.meetlaud.app.localization.PlatformText.back, Modifier.testTag("nav.back"), onClick = chrome.onBack)
                chrome.onMenu != null -> GlassCircleButton("line.3.horizontal.decrease", L10n.Nav.openMenu, Modifier.testTag("drawer.toggle"), onClick = chrome.onMenu)
            }
        }
        if (title != null) {
            Text(
                title,
                style = DsType.navTitle,
                color = Ds.primaryText.value,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.align(Alignment.Center).padding(horizontal = 64.dp),
            )
        }
        Row(Modifier.align(Alignment.CenterEnd), verticalAlignment = Alignment.CenterVertically, content = trailing)
    }
}

/** The large title of a root screen, at the top of its content. */
@Composable
fun LargeTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, style = DsType.largeTitle, color = Ds.primaryText.value, modifier = modifier.padding(horizontal = Spacing.medium).padding(top = Spacing.small, bottom = Spacing.small))
}

/** A whole screen: background, bar, and content under it. */
@Composable
fun Screen(
    title: String? = null,
    modifier: Modifier = Modifier,
    leading: (@Composable RowScope.() -> Unit)? = null,
    trailing: @Composable RowScope.() -> Unit = {},
    overlay: @Composable BoxScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    Box(modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            NavigationBar(title, leading = leading, trailing = trailing)
            content()
        }
        overlay()
    }
}

/** Padding that keeps a list's last row clear of the floating bars. */
@Composable
fun contentPadding(top: Dp = Spacing.medium): PaddingValues =
    PaddingValues(top = top, bottom = LocalNavigationChrome.current.bottomInset + Spacing.large)

@Composable
fun HSpace(width: Dp) = Spacer(Modifier.width(width))
