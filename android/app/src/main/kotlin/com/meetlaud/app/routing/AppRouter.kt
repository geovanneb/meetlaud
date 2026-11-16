package com.meetlaud.app.routing

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList

/**
 * The single source of navigation state, as AppRouter.swift. Each destination keeps its own path, so switching in
 * the side menu preserves where the person was.
 */
class AppRouter(selected: Destination = Destination.HOME) {
    var selected by mutableStateOf(selected)
        private set
    var isDrawerOpen by mutableStateOf(false)
    /** The recording screen, which floats above every destination. */
    var isRecorderPresented by mutableStateOf(false)
    private val paths = mutableStateMapOf<Destination, SnapshotStateList<AppRoute>>()

    fun select(destination: Destination) {
        selected = destination
        isDrawerOpen = false
    }

    fun path(destination: Destination): List<AppRoute> = paths[destination] ?: emptyList()

    fun setPath(path: List<AppRoute>, destination: Destination) {
        paths[destination] = mutableStateListOf<AppRoute>().apply { addAll(path) }
    }

    /** The side menu edge gesture only works at a root, to avoid fighting the back swipe. */
    val isAtRoot: Boolean get() = path(selected).isEmpty()

    /** Opens a screen on top of the current destination, keeping the person's place. */
    fun push(route: AppRoute) {
        paths.getOrPut(selected) { mutableStateListOf() }.add(route)
    }

    /** Goes back one screen. */
    fun pop() {
        paths[selected]?.let { if (it.isNotEmpty()) it.removeAt(it.lastIndex) }
    }

    fun open(route: AppRoute) {
        select(route.destination)
        if (route == AppRoute.Record) isRecorderPresented = true
        if (route.isPushed) paths.getOrPut(route.destination) { mutableStateListOf() }.add(route)
    }

    /** Returns false when the URL is not a valid route, which is a normal outcome for untrusted input. */
    fun open(url: Uri): Boolean {
        val route = DeepLink.route(url.toString()) ?: return false
        open(route)
        return true
    }
}

/** The router, for every screen below the shell, as `@Environment(AppRouter.self)`. */
val LocalRouter = androidx.compose.runtime.staticCompositionLocalOf<AppRouter> { error("No router") }
