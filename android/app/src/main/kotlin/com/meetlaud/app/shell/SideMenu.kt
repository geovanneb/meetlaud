package com.meetlaud.app.shell

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.IconSize
import com.meetlaud.app.designsystem.MeetlaudMark
import com.meetlaud.app.designsystem.Motion
import com.meetlaud.app.designsystem.PlainButton
import com.meetlaud.app.designsystem.Radius
import com.meetlaud.app.designsystem.SfIcon
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.designsystem.TapTarget
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.routing.Destination

@Composable
fun SideMenu(selected: Destination, onSelect: (Destination) -> Unit, onSearch: () -> Unit) {
    Column(
        Modifier.verticalScroll(rememberScrollState()).statusBarsPadding().padding(horizontal = Spacing.small).padding(top = Spacing.medium),
        verticalArrangement = Arrangement.spacedBy(Spacing.xSmall),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            MeetlaudMark(modifier = Modifier.padding(start = Spacing.medium))
            Spacer(Modifier.weight(1f))
            PlainButton(onSearch, Modifier.size(TapTarget).testTag("drawer.search"), label = L10n.Library.search) {
                Spacer(Modifier.weight(1f))
                SfIcon("magnifyingglass", size = IconSize.icon)
                Spacer(Modifier.weight(1f))
            }
        }
        Destination.primary.forEach { Row(it, it == selected, onSelect) }
        HorizontalDivider(Modifier.padding(vertical = Spacing.small), thickness = 0.5.dp, color = Ds.separator.value)
        Destination.secondary.forEach { Row(it, it == selected, onSelect) }
    }
}

@Composable
private fun Row(destination: Destination, isSelected: Boolean, onSelect: (Destination) -> Unit) {
    val background by animateColorAsState(if (isSelected) Ds.selection.value else Color.Transparent, Motion.quick(), label = "row")
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.small))
            .background(background)
            .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button) { onSelect(destination) }
            .semantics { selected = isSelected }
            .testTag("drawer.item.${destination.raw}")
            .padding(Spacing.medium),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SfIcon(destination.symbol, Modifier.width(Spacing.large), size = DsType.menuRow.fontSize)
        Spacer(Modifier.width(Spacing.medium))
        Text(destination.title, style = DsType.menuRow, color = Ds.primaryText.value)
    }
}

private val Destination.title: String
    get() = when (this) {
        Destination.HOME -> L10n.Nav.home
        Destination.LIBRARY -> L10n.Nav.library
        Destination.ASK -> L10n.Nav.ask
        Destination.TOOLS -> L10n.Nav.tools
        Destination.SETTINGS -> L10n.Nav.settings
        Destination.HELP -> L10n.Nav.help
    }

private val Destination.symbol: String
    get() = when (this) {
        Destination.HOME -> "house"
        Destination.LIBRARY -> "folder"
        Destination.ASK -> "sparkles"
        Destination.TOOLS -> "wrench.and.screwdriver"
        Destination.SETTINGS -> "gearshape"
        Destination.HELP -> "questionmark.circle"
    }
