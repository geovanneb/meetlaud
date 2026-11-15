package com.meetlaud.app

import androidx.compose.runtime.Composable
import com.meetlaud.app.feature.home.HomeScreen
import com.meetlaud.app.feature.tools.CategoryTemplatesScreen
import com.meetlaud.app.feature.tools.TemplateDetailScreen
import com.meetlaud.app.feature.tools.ToolsScreen
import com.meetlaud.domain.TemplateCategory
import com.meetlaud.app.feature.ask.AskScreen
import com.meetlaud.app.feature.ask.MemoryScreen
import com.meetlaud.app.feature.ask.ScopedChatScreen
import com.meetlaud.domain.AskScope
import com.meetlaud.app.feature.detail.DetailScreen
import androidx.compose.runtime.remember
import com.meetlaud.app.feature.library.LibraryScreen
import com.meetlaud.app.feature.library.SearchScreen
import com.meetlaud.app.feature.library.TrashScreen
import com.meetlaud.app.routing.AppRoute
import com.meetlaud.app.routing.Destination
import com.meetlaud.app.feature.settings.AboutScreen
import com.meetlaud.app.feature.models.AIModelsScreen
import com.meetlaud.app.feature.models.CompareModelsScreen
import com.meetlaud.app.feature.models.ModelDetailScreen
import com.meetlaud.app.feature.models.ModelStorageScreen
import com.meetlaud.app.feature.models.NetworkActivityScreen
import com.meetlaud.app.feature.models.PreferencesScreen
import com.meetlaud.app.feature.models.RoleModelsScreen
import com.meetlaud.app.feature.home.CalendarScreen
import com.meetlaud.app.feature.people.PeopleScreen
import com.meetlaud.app.feature.people.PersonScreen
import com.meetlaud.app.feature.settings.CalendarsModel
import com.meetlaud.app.feature.settings.CalendarsScreen
import com.meetlaud.app.feature.settings.HelpScreen
import com.meetlaud.app.feature.settings.LicensesScreen
import com.meetlaud.app.feature.settings.NotificationsScreen
import com.meetlaud.app.feature.settings.PrivacySecurityScreen
import com.meetlaud.app.feature.settings.SettingsScreen
import com.meetlaud.app.feature.settings.StorageBackupScreen
import com.meetlaud.app.feature.settings.VocabularyScreen

/** The only place that knows every feature, as Composition.swift. */
class Composition(private val container: AppContainer) {
    @Composable
    fun screen(destination: Destination) {
        when (destination) {
            Destination.HOME -> HomeScreen(
                model = container.home,
                center = container.transcription,
                onRecord = { container.recorder.record() },
                onRecordEvent = ::record,
                onImport = { container.library.presentFilePicker() },
            )
            Destination.LIBRARY -> LibraryScreen(container.library, container.transcription)
            Destination.ASK -> AskScreen(container.ask)
            Destination.TOOLS -> ToolsScreen(container.summaries, container.skills, container.connectors, { null }, container::transcribedRecordings)
            Destination.SETTINGS -> SettingsScreen()
            Destination.HELP -> HelpScreen()
        }
    }

    @Composable
    fun screen(route: AppRoute) {
        when (route) {
            is AppRoute.Recording -> {
                // The model loaded for this screen must survive redraws, as @State keeps it on iOS.
                val model = remember(route) { container.detailModel(route.id, route.at) }
                DetailScreen(model)
            }
            is AppRoute.Ask -> route.recording?.let { ScopedChatScreen(container.ask, AskScope.Recording(it)) } ?: AskScreen(container.ask)
            is AppRoute.AskFolder -> ScopedChatScreen(container.ask, AskScope.Folder(route.folder))
            is AppRoute.AskSkill -> ScopedChatScreen(container.ask, AskScope.Library, container.skills.skill(route.skill))
            AppRoute.Memory -> MemoryScreen(container.ask)
            is AppRoute.Template -> TemplateDetailScreen(route.id, container.summaries, container::transcribedRecordings)
            is AppRoute.TemplateCategory -> CategoryTemplatesScreen(TemplateCategory.entries.first { it.raw == route.raw }, container.summaries)
            AppRoute.Search -> SearchScreen(container.library)
            AppRoute.Trash -> TrashScreen(container.library)
            AppRoute.ModelSettings -> AIModelsScreen(container.models)
            is AppRoute.ModelRole -> RoleModelsScreen(route.raw, container.models)
            is AppRoute.ModelDetail -> ModelDetailScreen(route.id, route.role, container.models)
            is AppRoute.CompareModels -> CompareModelsScreen(route.role, route.showsAll, container.models)
            AppRoute.ModelStorage -> ModelStorageScreen(container.models)
            AppRoute.Preferences -> PreferencesScreen(container.models)
            AppRoute.NetworkActivity -> NetworkActivityScreen(container.models)
            AppRoute.People -> PeopleScreen(container.people)
            is AppRoute.Person -> PersonScreen(route.id, container.people)
            AppRoute.Calendar -> CalendarScreen(container.home, ::record)
            AppRoute.Notifications -> NotificationsScreen(container.system)
            AppRoute.About -> AboutScreen(container.versionText)
            AppRoute.Licenses -> LicensesScreen(container.licensesText)
            AppRoute.HelpCenter -> HelpScreen()
            AppRoute.Privacy -> PrivacySecurityScreen(container.system, container.lock)
            AppRoute.Storage -> StorageBackupScreen(container.system)
            AppRoute.Calendars -> CalendarsScreen(remember { CalendarsModel(container.calendarProvider, container.calendarChoices) })
            AppRoute.Vocabulary -> VocabularyScreen(container.library.folders)
            // The recorder is a cover over everything, not a screen in the stack, as on iOS.
            AppRoute.Record -> Unit
        }
    }

    private fun record(event: com.meetlaud.domain.CalendarEvent) {
        // A recording with no name gets the usual dated one, which beats an empty title.
        container.recorder.record(if (event.hasTitle) event.title else null, event.attendees)
    }
}
