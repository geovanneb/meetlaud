package com.meetlaud.app.feature.shared

import com.meetlaud.app.localization.Strings
import java.util.Locale

/** "English", "Japonês": a language as the interface names it, capitalized as a menu item. */
fun languageName(code: String): String =
    Locale.forLanguageTag(code).getDisplayLanguage(Strings.locale()).replaceFirstChar { it.titlecase(Strings.locale()) }
