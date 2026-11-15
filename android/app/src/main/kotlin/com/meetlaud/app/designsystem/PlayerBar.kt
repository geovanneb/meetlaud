package com.meetlaud.app.designsystem

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.text.NumberFormat

data class PlayerBarLabels(val play: String, val pause: String, val back: String, val forward: String, val position: String, val speed: String)

/** Timeline with markers, transport controls, and speed, as PlayerBar.swift. */
@Composable
fun PlayerBar(
    time: Double,
    duration: Double,
    isPlaying: Boolean,
    markers: List<Double>,
    rate: Float,
    labels: PlayerBarLabels,
    onSeek: (Double) -> Unit,
    onToggle: () -> Unit,
    onRate: (Float) -> Unit,
    modifier: Modifier = Modifier,
) {
    var scrubbing by remember { mutableStateOf<Double?>(null) }
    val total = maxOf(duration, 1.0)
    Column(modifier.fillMaxWidth().padding(horizontal = Spacing.medium, vertical = Spacing.small), verticalArrangement = Arrangement.spacedBy(Spacing.small)) {
        Box {
            IosSlider(
                scrubbing ?: time, 0.0..total, { scrubbing = it },
                onFinished = {
                    scrubbing?.let(onSeek)
                    scrubbing = null
                },
                label = labels.position, valueText = time.clock,
            )
            val tint = Ds.action.value
            Box(Modifier.fillMaxWidth().height(12.dp).padding(horizontal = 14.dp).clearAndSetSemantics {}) {
                Canvas(Modifier.fillMaxWidth().height(12.dp)) {
                    for (marker in markers) {
                        val x = size.width * (marker / total).toFloat()
                        drawRoundRect(tint, Offset(x - 1.5f, 0f), Size(3.dp.toPx(), 12.dp.toPx()), CornerRadius(1.5f.dp.toPx()))
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().clearAndSetSemantics {}) {
            Text((scrubbing ?: time).clock, style = DsType.timestamp, color = Ds.secondaryText.value)
            Spacer(Modifier.weight(1f))
            Text(duration.clock, style = DsType.timestamp, color = Ds.secondaryText.value)
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.large)) {
            var speedOpen by remember { mutableStateOf(false) }
            Box {
                PlainButton({ speedOpen = true }, Modifier.size(TapTarget).testTag("player.speed"), label = labels.speed) {
                    Spacer(Modifier.weight(1f))
                    Text(rateText(rate), style = DsType.timestamp, color = Ds.primaryText.value)
                    Spacer(Modifier.weight(1f))
                }
                IosMenu(speedOpen, { speedOpen = false }, RATES.map { value -> MenuAction(rateText(value), isChecked = value == rate) { onRate(value) } })
            }
            Spacer(Modifier.weight(1f))
            PlainButton({ onSeek(time - 15) }, Modifier.size(TapTarget), label = labels.back) {
                SkipSymbol("gobackward", "15")
            }
            PlainButton(onToggle, Modifier.size(TapTarget).testTag("player.toggle"), label = if (isPlaying) labels.pause else labels.play) {
                Spacer(Modifier.weight(1f))
                SfIcon(if (isPlaying) "pause.fill" else "play.fill", size = IconSize.hero)
                Spacer(Modifier.weight(1f))
            }
            PlainButton({ onSeek(time + 30) }, Modifier.size(TapTarget), label = labels.forward) {
                SkipSymbol("goforward", "30")
            }
            Spacer(Modifier.weight(1f))
            Spacer(Modifier.size(TapTarget))
        }
    }
}

val RATES = listOf(0.75f, 1f, 1.25f, 1.5f, 2f)

/** "1.25×", without trailing zeros, as Float.formatted(). */
fun rateText(rate: Float): String = NumberFormat.getNumberInstance(com.meetlaud.app.localization.Strings.locale()).apply { maximumFractionDigits = 2 }.format(rate) + "×"

/** gobackward.15 and goforward.30: a circular arrow with its number inside. */
@Composable
private fun SkipSymbol(symbol: String, number: String) {
    Box(Modifier.size(TapTarget), contentAlignment = Alignment.Center) {
        SfIcon(symbol, size = 30.dp)
        Text(number, style = DsType.badge.copy(fontSize = 9.sp, fontWeight = FontWeight.SemiBold), color = Ds.primaryText.value)
    }
}
