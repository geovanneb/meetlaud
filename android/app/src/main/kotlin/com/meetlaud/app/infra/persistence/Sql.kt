package com.meetlaud.app.infra.persistence

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.SQLiteStatement
import androidx.sqlite.execSQL
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * A thin layer over one SQLite connection, with GRDB's encodings so that the file is the same one the iOS app writes:
 * dates as UTC text, booleans as 0 and 1, vectors as raw little-endian floats.
 */
internal class Sql(val connection: SQLiteConnection) {
    fun execute(sql: String, vararg arguments: Any?) {
        connection.prepare(sql).use { statement ->
            bind(statement, arguments)
            while (statement.step()) Unit
        }
    }

    fun <T> query(sql: String, vararg arguments: Any?, map: (Row) -> T?): List<T> =
        connection.prepare(sql).use { statement ->
            bind(statement, arguments)
            val names = (0 until statement.getColumnCount()).associateBy { statement.getColumnName(it) }
            val result = mutableListOf<T>()
            val row = Row(statement, names)
            while (statement.step()) map(row)?.let(result::add)
            result
        }

    fun <T> one(sql: String, vararg arguments: Any?, map: (Row) -> T?): T? = query(sql, *arguments, map = map).firstOrNull()

    /** Runs the block in one transaction, so that nothing is ever half written. */
    fun <T> transaction(block: Sql.() -> T): T {
        connection.execSQL("BEGIN IMMEDIATE")
        try {
            val result = block()
            connection.execSQL("COMMIT")
            return result
        } catch (error: Throwable) {
            runCatching { connection.execSQL("ROLLBACK") }
            throw error
        }
    }

    private fun bind(statement: SQLiteStatement, arguments: Array<out Any?>) {
        arguments.forEachIndexed { offset, value ->
            val index = offset + 1
            when (value) {
                null -> statement.bindNull(index)
                is String -> statement.bindText(index, value)
                is Boolean -> statement.bindLong(index, if (value) 1 else 0)
                is Int -> statement.bindLong(index, value.toLong())
                is Long -> statement.bindLong(index, value)
                is Double -> statement.bindDouble(index, value)
                is Float -> statement.bindDouble(index, value.toDouble())
                is ByteArray -> statement.bindBlob(index, value)
                is Instant -> statement.bindText(index, GrdbDate.format(value))
                else -> error("Cannot bind ${value::class}")
            }
        }
    }
}

internal class Row(private val statement: SQLiteStatement, private val names: Map<String, Int>) {
    private fun index(name: String) = names[name] ?: error("No column $name")

    fun isNull(name: String) = statement.isNull(index(name))
    fun string(name: String): String = statement.getText(index(name))
    fun optString(name: String): String? = if (isNull(name)) null else string(name)
    fun double(name: String): Double = statement.getDouble(index(name))
    fun optDouble(name: String): Double? = if (isNull(name)) null else double(name)
    fun long(name: String): Long = statement.getLong(index(name))
    fun int(name: String): Int = long(name).toInt()
    fun bool(name: String): Boolean = long(name) != 0L
    fun blob(name: String): ByteArray = statement.getBlob(index(name))
    fun optBlob(name: String): ByteArray? = if (isNull(name)) null else blob(name)
    fun date(name: String): Instant = GrdbDate.parse(string(name))
    fun optDate(name: String): Instant? = if (isNull(name)) null else date(name)
}

/** GRDB stores a Date as "yyyy-MM-dd HH:mm:ss.SSS" in UTC, and reads a few more shapes. */
internal object GrdbDate {
    private val writer = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS").withZone(ZoneOffset.UTC)

    fun format(instant: Instant): String = writer.format(instant)

    fun parse(text: String): Instant {
        val normalized = text.trim().replace('T', ' ').removeSuffix("Z")
        val withFraction = when {
            normalized.length == 10 -> "$normalized 00:00:00.000"
            normalized.length == 16 -> "$normalized:00.000"
            normalized.length == 19 -> "$normalized.000"
            else -> normalized.padEnd(23, '0').take(23)
        }
        return LocalDateTime.parse(withFraction, DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS")).toInstant(ZoneOffset.UTC)
    }
}

/** Float vectors as raw little-endian bytes, as Swift's `withUnsafeBytes` writes them on every Apple device. */
internal object Vectors {
    fun encode(vector: List<Float>): ByteArray {
        val buffer = ByteBuffer.allocate(vector.size * 4).order(ByteOrder.LITTLE_ENDIAN)
        vector.forEach { buffer.putFloat(it) }
        return buffer.array()
    }

    fun decode(data: ByteArray?): List<Float> {
        if (data == null) return emptyList()
        val buffer = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
        return List(data.size / 4) { buffer.getFloat() }
    }
}
