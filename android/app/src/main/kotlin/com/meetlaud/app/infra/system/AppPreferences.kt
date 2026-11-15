package com.meetlaud.app.infra.system

import android.content.Context
import android.content.SharedPreferences
import com.meetlaud.domain.Preferences
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import org.json.JSONArray

/** UserDefaults on Android: one SharedPreferences file, with the same keys as the iOS app. */
class AppPreferences(context: Context, name: String = "meetlaud") : Preferences {
    val shared: SharedPreferences = context.getSharedPreferences(name, Context.MODE_PRIVATE)

    override fun string(key: String): String? = shared.getString(key, null)
    override fun setString(key: String, value: String?) = shared.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    override fun bool(key: String): Boolean? = if (shared.contains(key)) shared.getBoolean(key, false) else null
    override fun setBool(key: String, value: Boolean) = shared.edit().putBoolean(key, value).apply()
    override fun double(key: String): Double? = if (shared.contains(key)) java.lang.Double.longBitsToDouble(shared.getLong(key, 0)) else null
    override fun setDouble(key: String, value: Double) = shared.edit().putLong(key, java.lang.Double.doubleToRawLongBits(value)).apply()

    /** Lists keep their order, which a string set would lose. */
    override fun stringList(key: String): List<String>? = shared.getString(key, null)?.let { text ->
        runCatching { JSONArray(text).let { array -> List(array.length()) { array.getString(it) } } }.getOrNull()
    }

    override fun setStringList(key: String, value: List<String>?) =
        shared.edit().apply { if (value == null) remove(key) else putString(key, JSONArray(value).toString()) }.apply()

    override fun remove(key: String) = shared.edit().remove(key).apply()
    override fun clear() = shared.edit().clear().apply()

    override val changes: Flow<String> = callbackFlow {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key -> if (key != null) trySend(key) }
        shared.registerOnSharedPreferenceChangeListener(listener)
        awaitClose { shared.unregisterOnSharedPreferenceChangeListener(listener) }
    }
}
