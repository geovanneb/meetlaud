package com.meetlaud.app.designsystem

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

/** The drawer's math, the same as DrawerGeometry in DrawerContainer.swift, kept pure so it can be tested. */
object DrawerGeometry {
    const val EDGE_ACTIVATION_WIDTH = 24f
    private const val WIDTH_FRACTION = 0.76f
    private const val MAXIMUM_WIDTH = 340f
    /** How much the page fades back with the menu open. */
    const val CONTENT_FADE = 0.43f
    /** How far a flick carries on, in seconds of its speed. */
    const val FLICK_REACH = 0.25f

    fun menuWidth(container: Float): Float = minOf(container * WIDTH_FRACTION, MAXIMUM_WIDTH)
    fun menuScale(progress: Float): Float = 0.97f + 0.03f * progress
    fun menuOpacity(progress: Float): Float = 0.6f + 0.4f * progress

    fun progress(isOpen: Boolean, translation: Float, menuWidth: Float): Float {
        if (menuWidth <= 0) return if (isOpen) 1f else 0f
        val start = if (isOpen) 1f else 0f
        return (start + translation / menuWidth).coerceIn(0f, 1f)
    }

    /** Where the drawer rests after a drag, using the predicted end so a quick flick counts. */
    fun settles(openFrom: Boolean, translation: Float, predictedTranslation: Float, menuWidth: Float): Boolean {
        val predicted = maxOf(abs(predictedTranslation), abs(translation)) * if (predictedTranslation < 0) -1 else 1
        return progress(openFrom, predicted, menuWidth) > 0.5f
    }
}

/**
 * Side menu for compact widths (D-001). The content slides aside, and the menu settles into place behind it,
 * growing slightly and fading in. With reduced motion, the menu fades in on top.
 */
@Composable
fun DrawerContainer(
    isOpen: Boolean,
    onOpenChange: (Boolean) -> Unit,
    isEdgeGestureEnabled: Boolean,
    closeLabel: String,
    menu: @Composable () -> Unit,
    content: @Composable () -> Unit,
) {
    val reduceMotion = LocalReduceMotion.current
    val progress = remember { Animatable(if (isOpen) 1f else 0f) }
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current

    LaunchedEffect(isOpen) {
        val target = if (isOpen) 1f else 0f
        if (progress.targetValue != target || progress.value != target) {
            progress.animateTo(target, if (reduceMotion) tween(200) else spring(Spring.DampingRatioNoBouncy, stiffness = 987f))
        }
    }
    BackHandler(isOpen) { onOpenChange(false) }

    BoxWithConstraints(Modifier.fillMaxSize().background(Ds.background.value)) {
        val widthPx = DrawerGeometry.menuWidth(with(density) { maxWidth.value }).let { with(density) { it.dp.toPx() } }
        val widthDp = with(density) { widthPx.toDp() }
        val p = progress.value

        Box(
            Modifier
                .width(widthDp)
                .fillMaxHeight()
                .background(Ds.background.value)
                .zIndex(if (reduceMotion) 1f else 0f)
                .graphicsLayer {
                    val scale = if (reduceMotion) 1f else DrawerGeometry.menuScale(p)
                    scaleX = scale
                    scaleY = scale
                    alpha = if (reduceMotion) p else DrawerGeometry.menuOpacity(p)
                }
                .then(if (p == 0f) Modifier.semantics { } else Modifier),
        ) {
            if (p > 0f || isOpen) menu()
        }

        val radius = if (reduceMotion) 0.dp else Radius.drawer * p
        Box(
            Modifier
                .fillMaxSize()
                .offset { IntOffset(if (reduceMotion) 0 else (widthPx * p).roundToInt(), 0) }
                .shadow(if (p > 0f) 16.dp * p else 0.dp, RoundedCornerShape(radius), clip = false, ambientColor = Color.Black.copy(alpha = 0.12f), spotColor = Color.Black.copy(alpha = 0.12f))
                .clip(RoundedCornerShape(radius))
                .background(Ds.background.value)
                .pointerInput(isOpen, isEdgeGestureEnabled, widthPx) {
                    // The drag only begins sideways, and from the left edge when closed, so lists keep their scroll.
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        val startX = down.position.x / density.density
                        if (!isOpen && (!isEdgeGestureEnabled || startX > DrawerGeometry.EDGE_ACTIVATION_WIDTH)) return@awaitEachGesture
                        val tracker = VelocityTracker()
                        var dx = 0f
                        var dy = 0f
                        var dragging = false
                        var origin = 0f
                        while (true) {
                            val event = awaitPointerEvent()
                            val change = event.changes.firstOrNull { it.id == down.id } ?: break
                            if (!change.pressed) break
                            dx += change.positionChange().x
                            dy += change.positionChange().y
                            tracker.addPosition(change.uptimeMillis, change.position)
                            if (!dragging) {
                                if (abs(dx) < viewConfiguration.touchSlop && abs(dy) < viewConfiguration.touchSlop) continue
                                val sideways = abs(dx) > abs(dy) && (if (isOpen) dx < 0 else dx > 0)
                                if (!sideways) return@awaitEachGesture
                                dragging = true
                                origin = dx
                            }
                            change.consume()
                            val value = DrawerGeometry.progress(isOpen, dx - origin, widthPx)
                            scope.launch { progress.snapTo(value) }
                        }
                        if (dragging) {
                            val velocity = tracker.calculateVelocity().x
                            val settled = DrawerGeometry.settles(isOpen, dx - origin, dx - origin + velocity * DrawerGeometry.FLICK_REACH, widthPx)
                            scope.launch {
                                progress.animateTo(if (settled) 1f else 0f, spring(Spring.DampingRatioNoBouncy, stiffness = 987f))
                            }
                            if (settled != isOpen) onOpenChange(settled)
                        }
                    }
                },
        ) {
            content()
            if (p > 0f) {
                Box(Modifier.fillMaxSize().background(Ds.background.value.copy(alpha = DrawerGeometry.CONTENT_FADE * p)))
            }
            if (isOpen) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .clickable(remember { MutableInteractionSource() }, indication = null) { onOpenChange(false) }
                        .semantics { contentDescription = closeLabel },
                )
            }
        }
    }
}
