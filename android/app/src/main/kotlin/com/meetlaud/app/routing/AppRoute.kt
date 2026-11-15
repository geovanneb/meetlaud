package com.meetlaud.app.routing

import com.meetlaud.domain.FolderID
import com.meetlaud.domain.RecordingID
import com.meetlaud.domain.TimeInterval

/** Top-level destinations, in side menu order. */
enum class Destination(val raw: String) {
    HOME("home"), LIBRARY("library"), ASK("ask"), TOOLS("tools"), SETTINGS("settings"), HELP("help");

    companion object {
        /** Destinations shown above the divider in the side menu. */
        val primary = listOf(HOME, LIBRARY, ASK, TOOLS)
        /** Destinations shown below the divider in the side menu. */
        val secondary = listOf(SETTINGS, HELP)
    }
}

/** Every place the app can navigate to. Taps, widgets, shortcuts, and notifications all use this type. */
sealed interface AppRoute {
    /**
     * Shows the recording entry point. This never starts capture: any app can open a `meetlaud://` URL, so a URL
     * must not be able to turn on the microphone (D-024).
     */
    data object Record : AppRoute
    data class Recording(val id: RecordingID, val at: TimeInterval? = null) : AppRoute
    data class Ask(val recording: RecordingID? = null) : AppRoute
    data class AskFolder(val folder: FolderID) : AppRoute
    /** A new chat that answers the way a skill says. The id comes from a tap in Tools, never from a URL. */
    data class AskSkill(val skill: String) : AppRoute
    data object ModelSettings : AppRoute
    /** The models screens iOS opens with NavigationLinks, which have no route of their own. */
    data class ModelRole(val raw: String) : AppRoute
    data class ModelDetail(val id: String, val role: String) : AppRoute
    data class CompareModels(val role: String, val showsAll: Boolean) : AppRoute
    data object ModelStorage : AppRoute
    data object Search : AppRoute
    data object Trash : AppRoute
    data object Calendar : AppRoute
    data object Preferences : AppRoute
    data object NetworkActivity : AppRoute
    data object Licenses : AppRoute
    data object People : AppRoute
    /** One saved person. iOS opens it with a NavigationLink, which has no route of its own. */
    data class Person(val id: String) : AppRoute
    data object Memory : AppRoute
    data object Storage : AppRoute
    data object Notifications : AppRoute
    data object Calendars : AppRoute
    data object Vocabulary : AppRoute
    data object Privacy : AppRoute
    data object About : AppRoute
    data object HelpCenter : AppRoute
    /** A template in Tools, which iOS opens with a NavigationLink inside the same stack. */
    data class Template(val id: String) : AppRoute
    /** Every template in one category, the same way. */
    data class TemplateCategory(val raw: String) : AppRoute

    val destination: Destination
        get() = when (this) {
            Record, Calendar -> Destination.HOME
            is Recording, Search, Trash, is AskFolder -> Destination.LIBRARY
            is Ask, is AskSkill -> Destination.ASK
            is Template, is TemplateCategory -> Destination.TOOLS
            else -> Destination.SETTINGS
        }

    /** Whether this route pushes a screen, instead of only selecting a destination. */
    val isPushed: Boolean
        get() = !(this == Record || this == Ask(null))
}
