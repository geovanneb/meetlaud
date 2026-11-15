package com.meetlaud.app.designsystem

import android.annotation.SuppressLint
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import com.meetlaud.app.R

private val iconIds = HashMap<String, Int>()

/** The drawable that stands for an SF Symbol. Tools/android-icons makes one per symbol the iOS app uses. */
@SuppressLint("DiscouragedApi")
@Composable
fun sfIconId(symbol: String): Int {
    val context = LocalContext.current
    return remember(symbol) {
        iconIds.getOrPut(symbol) {
            val name = "sf_" + symbol.replace(Regex("[^a-z0-9]"), "_")
            context.resources.getIdentifier(name, "drawable", context.packageName).takeIf { it != 0 }
                ?: error("No icon for SF Symbol '$symbol'. Add it to Tools/android-icons.")
        }
    }
}

/**
 * Image(systemName:) on Android. Sized like a symbol inside text of `size`, so it scales with the font size as
 * SF Symbols scale with Dynamic Type.
 */
@Composable
fun SfIcon(
    symbol: String,
    modifier: Modifier = Modifier,
    tint: Color = Ds.primaryText.value,
    size: TextUnit = IconSize.row,
    contentDescription: String? = null,
) {
    val dp: Dp = with(LocalDensity.current) { size.toDp() } * 1.18f
    Icon(painterResource(sfIconId(symbol)), contentDescription, modifier.size(dp), tint = tint)
}

@Composable
fun SfIcon(symbol: String, size: Dp, modifier: Modifier = Modifier, tint: Color = Ds.primaryText.value, contentDescription: String? = null) {
    Icon(painterResource(sfIconId(symbol)), contentDescription, modifier.size(size), tint = tint)
}

/** The logo, tinted by the interface so that it works in Light and Dark. */
@Composable
fun MeetlaudMark(height: Dp = 22.dp, modifier: Modifier = Modifier) {
    Icon(
        painterResource(R.drawable.meetlaud_mark),
        contentDescription = null,
        modifier = modifier.size(height * (640f / 584f), height),
        tint = Ds.primaryText.value,
    )
}

/** record.circle: a ring with a dot inside, in the record color. Drawn, since it is the app's one red mark. */
@Composable
fun RecordSymbol(size: Dp = 22.dp, tint: androidx.compose.ui.graphics.Color = Ds.record.value) {
    androidx.compose.foundation.Canvas(Modifier.size(size)) {
        val stroke = this.size.minDimension * 0.09f
        drawCircle(tint, radius = this.size.minDimension / 2 - stroke / 2, style = androidx.compose.ui.graphics.drawscope.Stroke(stroke))
        drawCircle(tint, radius = this.size.minDimension * 0.25f)
    }
}
