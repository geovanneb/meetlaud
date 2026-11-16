package com.meetlaud.app.shell

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DrawerContainer
import com.meetlaud.app.designsystem.LocalReduceMotion
import com.meetlaud.app.designsystem.PromptBar
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.routing.AppRoute
import com.meetlaud.app.routing.AppRouter
import com.meetlaud.app.routing.Destination

/**
 * The app's navigation frame, as AppShellView.swift on a phone: a drawer, and one stack per destination. Destination
 * screens come in from the composition root, so this package knows no feature.
 */
@Composable
fun AppShell(
    router: AppRouter,
    content: @Composable (Destination) -> Unit,
    routeContent: @Composable (AppRoute) -> Unit,
    accessory: @Composable () -> Unit,
    recorder: @Composable () -> Unit,
) {
    DrawerContainer(
        isOpen = router.isDrawerOpen,
        onOpenChange = { router.isDrawerOpen = it },
        isEdgeGestureEnabled = router.isAtRoot,
        closeLabel = L10n.Nav.closeMenu,
        menu = { SideMenu(router.selected, onSelect = router::select, onSearch = { router.open(AppRoute.Search) }) },
    ) {
        Box(Modifier.fillMaxSize()) {
            Stack(router, content, routeContent)
            Box(Modifier.align(Alignment.BottomCenter).navigationBarsPadding()) { accessory() }
        }
    }
    // A full-screen cover: it rises from the bottom over every destination, as on iOS.
    androidx.compose.animation.AnimatedVisibility(
        router.isRecorderPresented,
        enter = androidx.compose.animation.slideInVertically(tween(350)) { it },
        exit = androidx.compose.animation.slideOutVertically(tween(300)) { it },
    ) { recorder() }
}

/** The stack of one destination. A push slides in from the right, as UINavigationController does. */
@Composable
private fun Stack(router: AppRouter, content: @Composable (Destination) -> Unit, routeContent: @Composable (AppRoute) -> Unit) {
    val destination = router.selected
    val path = router.path(destination)
    val reduceMotion = LocalReduceMotion.current
    val saveable = rememberSaveableStateHolder()
    BackHandler(path.isNotEmpty() && !router.isDrawerOpen) { router.pop() }

    // A key per screen: the destination, and how deep in its stack.
    data class Page(val destination: Destination, val depth: Int, val route: AppRoute?)
    val page = Page(destination, path.size, path.lastOrNull())

    AnimatedContent(
        targetState = page,
        contentKey = { "${it.destination}/${it.depth}" },
        transitionSpec = {
            when {
                initialState.destination != targetState.destination || reduceMotion -> fadeIn(tween(0)) togetherWith fadeOut(tween(0))
                targetState.depth > initialState.depth ->
                    slideInHorizontally(tween(350)) { it } togetherWith slideOutHorizontally(tween(350)) { -it / 3 }
                else -> slideInHorizontally(tween(350)) { -it / 3 } togetherWith slideOutHorizontally(tween(350)) { it }
            }
        },
        label = "stack",
    ) { current ->
        saveable.SaveableStateProvider("${current.destination}/${current.depth}") {
            val showsPrompt = current.depth == 0 && (current.destination == Destination.HOME || current.destination == Destination.LIBRARY)
            val chrome = NavigationChrome(
                onMenu = if (current.depth == 0) ({ router.isDrawerOpen = true }) else null,
                onBack = if (current.depth > 0) ({ router.pop() }) else null,
                bottomInset = if (showsPrompt) 72.dp else 0.dp,
            )
            CompositionLocalProvider(LocalNavigationChrome provides chrome) {
                Box(Modifier.fillMaxSize().background(Ds.background.value)) {
                    if (current.route == null) content(current.destination) else routeContent(current.route)
                    if (showsPrompt) {
                        Box(Modifier.align(Alignment.BottomCenter).navigationBarsPadding()) {
                            PromptBar(L10n.Home.askPlaceholder) { router.open(AppRoute.Ask(null)) }
                        }
                    }
                }
            }
        }
    }
}
