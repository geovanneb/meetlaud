package com.meetlaud.app.designsystem

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/** The size of everything that looks like the place to ask. A prompt looks the same before and after it opens. */
object PromptMetrics {
    val minimumHeight = 56.dp
    val cornerRadius = 28.dp
    val textInset = Spacing.large
}

/** Where a prompt sits: floating over the content, with the same margins on every screen. */
fun Modifier.promptPlacement(): Modifier = padding(horizontal = Spacing.medium).padding(bottom = Spacing.small)

/** The bar at the bottom of main screens, where a thumb already rests. */
@Composable
fun PromptBar(placeholder: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Row(
        modifier
            .promptPlacement()
            .fillMaxWidth()
            .defaultMinSize(minHeight = PromptMetrics.minimumHeight)
            .glass(CircleShape, LocalDarkTheme.current)
            .clip(CircleShape)
            .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = placeholder }
            .testTag("prompt.bar")
            .padding(horizontal = PromptMetrics.textInset, vertical = Spacing.small),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(placeholder, style = DsType.rowTitle, color = Ds.secondaryText.value, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(Spacing.small))
        SfIcon("sparkles", tint = Ds.secondaryText.value)
    }
}
