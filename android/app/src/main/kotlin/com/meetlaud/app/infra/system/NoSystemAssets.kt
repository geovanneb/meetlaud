package com.meetlaud.app.infra.system

import com.meetlaud.domain.SystemSpeechAssets

/** Android has no system-managed speech models, so this is the real answer. */
object NoSystemAssets : SystemSpeechAssets {
    override suspend fun isInstalled(language: String): Boolean = false
    override suspend fun install(language: String) = Unit
}
