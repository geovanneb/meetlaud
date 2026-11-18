package com.meetlaud.domain

/**
 * The privacy policy in docs/, shipped inside the app so it can be read without a connection. Google Play and the
 * App Store ask for it inside the app, not only on the store listing. The same as PrivacyPolicy.swift.
 */
object PrivacyPolicy {
    /** The bundled file for the app's language, such as "PRIVACY.ja". English for any other language. */
    fun fileName(language: String?): String {
        val code = (language ?: "").lowercase()
        return when {
            code.startsWith("ja") -> "PRIVACY.ja"
            code.startsWith("pt") -> "PRIVACY.pt-BR"
            code.startsWith("es") -> "PRIVACY.es"
            else -> "PRIVACY"
        }
    }

    /** Leaves out the line that links to the other languages: in the app, the language is already the person's own. */
    fun readable(markdown: String): String = markdown.split("\n").filterNot { it.contains("](PRIVACY") }.joinToString("\n")
}
