package com.meetlaud.app.infra.system

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.provider.CalendarContract
import com.meetlaud.domain.CalendarAccess
import com.meetlaud.domain.CalendarEvent
import com.meetlaud.domain.CalendarProvider
import com.meetlaud.domain.CalendarSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Instant

/**
 * The calendars already on the phone, read through CalendarContract. Nothing leaves the device, and the app never
 * writes to a calendar. The counterpart of SystemCalendarProvider.swift.
 */
class SystemCalendarProvider(private val context: Context, private val permissions: Permissions) : CalendarProvider {
    private val permission = Manifest.permission.READ_CALENDAR

    override val access: CalendarAccess
        get() = when {
            permissions.isGranted(permission) -> CalendarAccess.GRANTED
            permissions.wasAsked(permission) -> CalendarAccess.DENIED
            else -> CalendarAccess.UNDETERMINED
        }

    override suspend fun requestAccess(): Boolean = permissions.request(permission)

    override suspend fun events(from: Instant, to: Instant): List<CalendarEvent> = withContext(Dispatchers.IO) {
        if (!permissions.isGranted(permission)) return@withContext emptyList()
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, from.toEpochMilli())
            ContentUris.appendId(it, to.toEpochMilli())
        }.build()
        val columns = arrayOf(
            CalendarContract.Instances.EVENT_ID, CalendarContract.Instances.TITLE, CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END, CalendarContract.Instances.ALL_DAY, CalendarContract.Instances.STATUS,
            CalendarContract.Instances.SELF_ATTENDEE_STATUS, CalendarContract.Instances.CALENDAR_ID,
        )
        val events = mutableListOf<CalendarEvent>()
        runCatching {
            context.contentResolver.query(uri, columns, null, null, "${CalendarContract.Instances.BEGIN} ASC")?.use { cursor ->
                while (cursor.moveToNext()) {
                    // All-day, cancelled, and declined events stay out, as on iOS.
                    if (cursor.getInt(4) == 1) continue
                    if (cursor.getInt(5) == CalendarContract.Instances.STATUS_CANCELED) continue
                    if (cursor.getInt(6) == CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED) continue
                    val eventID = cursor.getLong(0)
                    events.add(
                        CalendarEvent(
                            id = "$eventID@${cursor.getLong(2)}",
                            title = cursor.getString(1) ?: "",
                            start = Instant.ofEpochMilli(cursor.getLong(2)),
                            end = Instant.ofEpochMilli(cursor.getLong(3)),
                            attendees = attendees(eventID),
                            calendarID = cursor.getLong(7).toString(),
                        ),
                    )
                }
            }
        }
        events
    }

    /** People invited, by name, leaving out the person who owns the phone. */
    private fun attendees(eventID: Long): List<String> {
        val names = mutableListOf<String>()
        runCatching {
            context.contentResolver.query(
                CalendarContract.Attendees.CONTENT_URI,
                arrayOf(CalendarContract.Attendees.ATTENDEE_NAME, CalendarContract.Attendees.ATTENDEE_EMAIL, CalendarContract.Attendees.ATTENDEE_RELATIONSHIP),
                "${CalendarContract.Attendees.EVENT_ID} = ?", arrayOf(eventID.toString()), null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    if (cursor.getInt(2) == CalendarContract.Attendees.RELATIONSHIP_ORGANIZER && names.isEmpty() && cursor.count == 1) continue
                    val name = cursor.getString(0)?.takeIf { it.isNotBlank() } ?: cursor.getString(1)?.substringBefore('@') ?: continue
                    names.add(name)
                }
            }
        }
        return names
    }

    override suspend fun calendars(): List<CalendarSource> = withContext(Dispatchers.IO) {
        if (!permissions.isGranted(permission)) return@withContext emptyList()
        val list = mutableListOf<CalendarSource>()
        runCatching {
            context.contentResolver.query(
                CalendarContract.Calendars.CONTENT_URI,
                arrayOf(
                    CalendarContract.Calendars._ID, CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
                    CalendarContract.Calendars.ACCOUNT_NAME, CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.Calendars.CALENDAR_COLOR,
                ),
                null, null, null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val color = cursor.getInt(4)
                    list.add(
                        CalendarSource(
                            id = cursor.getLong(0).toString(),
                            title = cursor.getString(1) ?: "",
                            account = cursor.getString(2) ?: "",
                            accountID = "${cursor.getString(3)}/${cursor.getString(2)}",
                            tint = CalendarSource.Tint(((color shr 16) and 0xFF) / 255.0, ((color shr 8) and 0xFF) / 255.0, (color and 0xFF) / 255.0),
                        ),
                    )
                }
            }
        }
        list
    }
}
