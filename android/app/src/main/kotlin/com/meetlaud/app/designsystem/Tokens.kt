package com.meetlaud.app.designsystem

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/** True when the app draws in Dark. Set once by MeetlaudTheme from the person's choice (AppTheme). */
val LocalDarkTheme = staticCompositionLocalOf { false }

private fun rgb(value: Long) = Color(0xFF000000 or value)

/** A color with a Light and a Dark value, as the iOS asset colors have. */
class DsColor(private val light: Long, private val dark: Long) {
    val value: Color
        @Composable @ReadOnlyComposable get() = if (LocalDarkTheme.current) rgb(dark) else rgb(light)

    fun resolve(isDark: Boolean): Color = if (isDark) rgb(dark) else rgb(light)
}

/**
 * Semantic colors, the same values as ios/Packages/UI/DesignSystem/Sources/Tokens.swift. Features use these, never
 * raw values.
 */
object Ds {
    val background = DsColor(0xF9F9F9, 0x0F0F0F)
    val surface = DsColor(0xFFFFFF, 0x1C1C1E)
    /** Primary text. */
    val primaryText = DsColor(0x111111, 0xF5F5F5)
    /** Secondary text. */
    val secondaryText = DsColor(0x505050, 0xB8B8B8)
    val selection = DsColor(0xEBEBEB, 0x2C2C2E)
    /** Reserved for recording. Using it elsewhere weakens what it means. */
    val record = DsColor(0xC62A2F, 0xFF6369)
    val action = DsColor(0x2F6FD0, 0x5E9BF0)
    /** Text and icons on top of `action`. White fails contrast on the lighter blue of Dark Mode. */
    val onAction = DsColor(0xFFFFFF, 0x0F0F0F)
    /** Work that finished well. Never the only sign, a symbol always goes with it. */
    val positive = DsColor(0x2E7D32, 0x6CCB72)
    /** Something that needs the person, without being an error. */
    val attention = DsColor(0x9A5B00, 0xF2B04E)
    /** The empty part of a bar or a ring. */
    val track = DsColor(0xE4E4E4, 0x343437)
    /** iOS draws list separators in this gray. */
    val separator = DsColor(0xDCDCDE, 0x38383A)
    /** Parts of one whole, as in a storage bar. Red stays out: it belongs to recording. */
    val series = listOf(
        action,
        DsColor(0x1C8C84, 0x4CC7BD),
        DsColor(0x8A5CC7, 0xB494EE),
        DsColor(0xB36B00, 0xF0A94A),
        DsColor(0x7A7A7A, 0x9A9A9E),
    )
    /** Marks that tell kinds apart, such as template categories. */
    val accents = listOf(
        action,
        DsColor(0x14756E, 0x4CC7BD),
        DsColor(0x8A5CC7, 0xB494EE),
        DsColor(0x995C00, 0xF0A94A),
        DsColor(0x6B6B6B, 0xA8A8AD),
    )
}

object Spacing {
    val xSmall = 4.dp
    val small = 8.dp
    val compact = 12.dp
    val medium = 16.dp
    val large = 24.dp
    val xLarge = 32.dp
}

object Radius {
    val small = 8.dp
    val medium = 14.dp
    val drawer = 28.dp
}

/** Apple's minimum tap target. */
val TapTarget = 44.dp
