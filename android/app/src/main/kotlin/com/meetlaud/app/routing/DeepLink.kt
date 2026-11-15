package com.meetlaud.app.routing

import com.meetlaud.domain.RecordingID
import java.net.URI
import java.net.URLDecoder

/** Parses `meetlaud://` URLs. Input is untrusted, so anything unexpected returns null. */
object DeepLink {
    const val SCHEME = "meetlaud"

    fun route(url: String): AppRoute? {
        val uri = runCatching { URI(url) }.getOrNull() ?: return null
        if (uri.scheme?.lowercase() != SCHEME) return null
        val host = uri.host?.lowercase() ?: return null
        val path = (uri.rawPath ?: "").split("/").filter { it.isNotEmpty() }
        val query = (uri.rawQuery ?: "").split("&").filter { it.isNotEmpty() }.map {
            val parts = it.split("=", limit = 2)
            URLDecoder.decode(parts[0], "UTF-8") to parts.getOrNull(1)?.let { v -> URLDecoder.decode(v, "UTF-8") }
        }
        fun value(name: String) = query.firstOrNull { it.first == name }?.second

        return when {
            host == "record" && path.isEmpty() -> AppRoute.Record
            host == "recording" && path.size == 1 -> {
                val id = RecordingID.from(path[0]) ?: return null
                val rawTime = value("t") ?: return AppRoute.Recording(id, null)
                val time = rawTime.toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 } ?: return null
                AppRoute.Recording(id, time)
            }
            host == "ask" && path.isEmpty() -> {
                val raw = value("recording") ?: return AppRoute.Ask(null)
                RecordingID.from(raw)?.let { AppRoute.Ask(it) }
            }
            host == "settings" && path.size == 1 && path[0] == "models" -> AppRoute.ModelSettings
            else -> null
        }
    }
}
