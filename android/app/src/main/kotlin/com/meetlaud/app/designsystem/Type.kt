package com.meetlaud.app.designsystem

import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.meetlaud.app.R

/**
 * Inter stands in for SF Pro, which Apple licenses for its own platforms only. It is a variable font, so every
 * weight comes from one file. Scripts it lacks, such as Japanese, fall back to the system font.
 */
@OptIn(ExperimentalTextApi::class)
val Inter = FontFamily(
    listOf(FontWeight.Normal, FontWeight.Medium, FontWeight.SemiBold, FontWeight.Bold).map { weight ->
        Font(R.font.inter, weight, variationSettings = FontVariation.Settings(FontVariation.weight(weight.weight)))
    },
)

private fun style(size: Float, lineHeight: Float, tracking: Float, weight: FontWeight = FontWeight.Normal, digits: Boolean = false) =
    TextStyle(
        fontFamily = Inter,
        fontSize = size.sp,
        lineHeight = lineHeight.sp,
        // SF's tracking at each size, in points, turned into a share of the size.
        letterSpacing = (tracking / size).em,
        fontWeight = weight,
        fontFeatureSettings = if (digits) "tnum" else null,
        lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None),
    )

/**
 * The type scale, the same levels as Font.ds* in Tokens.swift, at the sizes of iOS's default Dynamic Type setting.
 * Sizes are in sp, so they follow the system font size the way Dynamic Type does.
 */
object DsType {
    /** The largest number on a screen, such as the recording timer. */
    val display = style(34f, 41f, 0.4f, FontWeight.SemiBold, digits = true)
    /** What a screen is about, in its content: a meeting's title, or "My files". */
    val pageTitle = style(22f, 28f, -0.26f, FontWeight.Bold)
    /** A large navigation title. */
    val largeTitle = style(34f, 41f, 0.4f, FontWeight.Bold)
    /** The title of an empty state or a locked screen. */
    val sectionTitle = style(20f, 25f, -0.45f, FontWeight.Bold)
    /** A heading inside a card or a document. */
    val heading = style(17f, 22f, -0.43f, FontWeight.SemiBold)
    /** The main line of a row, and running text. */
    val rowTitle = style(17f, 22f, -0.43f)
    /** A row in the side menu, which is read from further away than a list. */
    val menuRow = style(20f, 25f, -0.45f)
    /** The line under a row's title, and short status text. */
    val meta = style(15f, 20f, -0.23f)
    /** Hints, explanations, and anything else that supports a row. */
    val note = style(13f, 18f, -0.08f)
    /** A small tag next to a title. */
    val badge = style(12f, 16f, 0f)
    /** A moment in the audio. Digits keep their width. */
    val timestamp = style(13f, 18f, -0.08f, digits = true)
    /** The title in a navigation bar. */
    val navTitle = style(17f, 22f, -0.43f, FontWeight.SemiBold)
    val callout = style(16f, 21f, -0.31f)
}

/** Sizes of icons that stand in for SF Symbols at a text style, roughly the symbol's height at that size. */
object IconSize {
    val hero: TextUnit = 34.sp
    val icon: TextUnit = 20.sp
    val iconLarge: TextUnit = 22.sp
    val row: TextUnit = 17.sp
}
