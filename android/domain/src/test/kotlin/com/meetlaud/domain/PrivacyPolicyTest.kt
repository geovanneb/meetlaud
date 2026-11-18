package com.meetlaud.domain

import org.junit.Assert.assertEquals
import org.junit.Test

/** The same cases as PrivacyPolicyTests.swift. */
class PrivacyPolicyTest {
    @Test fun eachLanguageReadsItsOwnPolicy() {
        assertEquals("PRIVACY.ja", PrivacyPolicy.fileName("ja"))
        assertEquals("PRIVACY.pt-BR", PrivacyPolicy.fileName("pt-BR"))
        assertEquals("PRIVACY.pt-BR", PrivacyPolicy.fileName("pt"))
        assertEquals("PRIVACY.es", PrivacyPolicy.fileName("es-419"))
        assertEquals("PRIVACY", PrivacyPolicy.fileName("en"))
        assertEquals("PRIVACY", PrivacyPolicy.fileName("fr"))
        assertEquals("PRIVACY", PrivacyPolicy.fileName(null))
    }

    @Test fun theLinksToOtherLanguagesAreLeftOut() {
        val text = "# Privacy\n\nEnglish · [日本語](PRIVACY.ja.md) · [Español](PRIVACY.es.md)\n\nNothing leaves."
        assertEquals("# Privacy\n\n\nNothing leaves.", PrivacyPolicy.readable(text))
    }
}
