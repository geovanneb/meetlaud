package com.meetlaud.app.localization

import android.content.Context
import java.util.Locale

/**
 * The lookup behind the generated L10n, and the accessors that Swift writes by hand (Tools/android-strings lists
 * them in HANDWRITTEN). Every key lives in the iOS String Catalogs.
 */
object Strings {
    @Volatile private var context: Context? = null

    /** Called once by the Application, and again when the language changes. */
    fun install(context: Context) {
        this.context = context
    }

    fun text(key: String): String {
        val id = L10n.ids[key] ?: error("No string '$key' in the catalogs")
        // Tests on the JVM have no resources: the key itself stands in, as a missing translation would on iOS.
        return context?.getString(id) ?: key
    }

    fun locale(): Locale = context?.resources?.configuration?.locales?.get(0) ?: Locale.getDefault()

    /**
     * The phone's clock: the explicit 12 or 24 hour setting, or else the region's habit. iOS reads the region, never
     * the app's language, so an English interface in Brazil still shows 14:20.
     */
    fun uses24HourClock(): Boolean {
        val context = context ?: return true
        when (android.provider.Settings.System.getString(context.contentResolver, android.provider.Settings.System.TIME_12_24)) {
            "24" -> return true
            "12" -> return false
        }
        // The phone's own locale, not the app's language: on Android 13 the app can have a language of its own.
        val region = if (android.os.Build.VERSION.SDK_INT >= 33) {
            context.getSystemService(android.app.LocaleManager::class.java).systemLocales[0]
        } else {
            android.content.res.Resources.getSystem().configuration.locales[0]
        }
        return android.text.format.DateFormat.getBestDateTimePattern(region, "jm").contains('H')
    }
}

internal fun text(key: String): String = Strings.text(key)

/** String(format:) with the interface's locale, so numbers read the way the language writes them. */
internal fun format(pattern: String, vararg args: Any): String = String.format(Strings.locale(), pattern, *args)

fun L10n.Summary.templateName(name: String): String = sectionTitle(name)

fun L10n.Summary.sectionTitle(title: String): String = when (title) {
    "Summary" -> text("builtin.summary")
    "Meeting minutes" -> text("builtin.minutes")
    "Discussion summary" -> text("builtin.discussion")
    "One-on-one" -> text("builtin.oneonone")
    "Lecture notes" -> text("builtin.lecture")
    "Interview notes" -> text("builtin.interview")
    "Call notes" -> text("builtin.call")
    "Key points" -> text("builtin.key_points")
    "Decisions" -> text("builtin.decisions")
    "Action items" -> text("builtin.action_items")
    "Topics discussed" -> text("builtin.topics_discussed")
    "Positions" -> text("builtin.positions")
    "Agreements" -> text("builtin.agreements")
    "Open questions" -> text("builtin.open_questions")
    "Topics" -> text("builtin.topics")
    "Feedback" -> text("builtin.feedback")
    "Main ideas" -> text("builtin.main_ideas")
    "Key terms" -> text("builtin.key_terms")
    "To review" -> text("builtin.to_review")
    "Background" -> text("builtin.background")
    "Strengths" -> text("builtin.strengths")
    "Concerns" -> text("builtin.concerns")
    "Purpose" -> text("builtin.purpose")
    else -> title
}

fun L10n.Templates.category(raw: String): String = when (raw) {
    "meeting" -> text("templates.cat_meeting")
    "speech" -> text("templates.cat_speech")
    "interview" -> text("templates.cat_interview")
    "call" -> text("templates.cat_call")
    else -> text("templates.cat_general")
}

fun L10n.Skills.builtInName(id: String): String = when (id) {
    "followup" -> text("skills.followup.name")
    "brief" -> text("skills.brief.name")
    "objections" -> text("skills.objections.name")
    else -> id
}

fun L10n.Skills.builtInSummary(id: String): String = when (id) {
    "followup" -> text("skills.followup.summary")
    "brief" -> text("skills.brief.summary")
    "objections" -> text("skills.objections.summary")
    else -> id
}

fun L10n.Library.itemCount(count: Int): String =
    if (count == 1) text("library.item_count_one") else format(text("library.item_count"), count)

/**
 * Text only the Android app shows, from android/l10n/Platform.xcstrings: where the iOS text names iPhone, iOS, or
 * Face ID, Android says the same thing in its own words.
 */
object PlatformText {
    val back: String get() = text("android.back")
    val appLockNote: String get() = text("android.app_lock_note")
    val appLockUnavailable: String get() = text("android.app_lock_unavailable")
    val deviceBackup: String get() = text("android.device_backup")
    val deviceBackupNote: String get() = text("android.device_backup_note")
    val promiseBody: String get() = text("android.promise_body")
    val runStopped: String get() = text("android.run_stopped")
}
