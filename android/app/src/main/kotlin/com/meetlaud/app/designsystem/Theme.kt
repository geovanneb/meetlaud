package com.meetlaud.app.designsystem

import android.provider.Settings
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalContext
import com.meetlaud.domain.AppTheme

/** True when the person turned animations off, Android's Reduce Motion. */
val LocalReduceMotion = staticCompositionLocalOf { false }

/** The app's timing, as Motion.swift. Short and calm. */
object Motion {
    fun <T> quick(): FiniteAnimationSpec<T> = tween(160)
    fun <T> standard(): FiniteAnimationSpec<T> = tween(250)
    fun <T> drawer(): FiniteAnimationSpec<T> = spring(dampingRatio = 1f, stiffness = 987f)
    fun <T> reduced(): FiniteAnimationSpec<T> = tween(200)
}

@Composable
fun MeetlaudTheme(theme: AppTheme, content: @Composable () -> Unit) {
    val isDark = when (theme) {
        AppTheme.SYSTEM -> isSystemInDarkTheme()
        AppTheme.LIGHT -> false
        AppTheme.DARK -> true
    }
    val context = LocalContext.current
    val reduceMotion = remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
    // Material supplies only the pieces iOS has too (text fields, the keyboard cursor). Every color comes from Ds.
    val scheme = if (isDark) {
        darkColorScheme(primary = Ds.action.resolve(true), background = Ds.background.resolve(true), surface = Ds.surface.resolve(true))
    } else {
        lightColorScheme(primary = Ds.action.resolve(false), background = Ds.background.resolve(false), surface = Ds.surface.resolve(false))
    }
    CompositionLocalProvider(LocalDarkTheme provides isDark, LocalReduceMotion provides reduceMotion) {
        MaterialTheme(colorScheme = scheme) {
            CompositionLocalProvider(LocalTextStyle provides DsType.rowTitle, content = content)
        }
    }
}
