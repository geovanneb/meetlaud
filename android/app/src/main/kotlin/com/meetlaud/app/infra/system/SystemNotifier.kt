package com.meetlaud.app.infra.system

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import com.meetlaud.app.MainActivity
import com.meetlaud.app.R
import com.meetlaud.app.localization.L10n
import com.meetlaud.domain.CalendarEvent
import com.meetlaud.domain.LocalNotifier
import com.meetlaud.domain.NotificationPreferences
import java.time.Instant

/**
 * Local notifications only, as SystemNotifier.swift. The app has no push service, so no server could ever send one.
 * Reminders are alarms the system keeps, and a receiver posts them, so they arrive with the app closed.
 */
class SystemNotifier(private val context: Context, private val permissions: Permissions) : LocalNotifier {
    companion object {
        private const val CHANNEL = "notifications"
        private const val REMINDER_PREFIX = "reminder."
        private const val SCHEDULED_KEY = "notifications.scheduledReminders"
        internal const val EXTRA_ID = "id"
        internal const val EXTRA_TITLE = "title"
        internal const val EXTRA_BODY = "body"

        fun channel(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(CHANNEL, L10n.System.notificationsTitle, NotificationManager.IMPORTANCE_DEFAULT))
        }

        internal fun post(context: Context, id: String, title: String, body: String) {
            channel(context)
            val open = PendingIntent.getActivity(
                context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE,
            )
            val notification = Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .apply { if (body.isNotEmpty()) setContentText(body) }
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
            runCatching { context.getSystemService(NotificationManager::class.java).notify(id, 0, notification) }
        }
    }

    private val preferences = context.getSharedPreferences("meetlaud.notifier", Context.MODE_PRIVATE)

    override suspend fun requestAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= 33) permissions.request(Manifest.permission.POST_NOTIFICATIONS)
        else context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()

    override suspend fun notify(id: String, title: String, body: String) = post(context, id, title, body)

    override suspend fun scheduleReminders(events: List<CalendarEvent>, title: String) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        for (old in preferences.getStringSet(SCHEDULED_KEY, emptySet()).orEmpty()) alarms.cancel(reminder(old, "", ""))
        val scheduled = mutableSetOf<String>()
        val now = Instant.now()
        for (event in events) {
            val at = event.start.minusMillis((NotificationPreferences.REMINDER_LEAD * 1000).toLong())
            if (!at.isAfter(now)) continue
            val id = REMINDER_PREFIX + event.id
            // Inexact on purpose: exact alarms need a special permission, and a minute either way is fine here.
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at.toEpochMilli(), reminder(id, title, event.title))
            scheduled.add(id)
        }
        preferences.edit().putStringSet(SCHEDULED_KEY, scheduled).apply()
    }

    private fun reminder(id: String, title: String, body: String): PendingIntent = PendingIntent.getBroadcast(
        context, id.hashCode(),
        Intent(context, ReminderReceiver::class.java).setAction(id).putExtra(EXTRA_ID, id).putExtra(EXTRA_TITLE, title).putExtra(EXTRA_BODY, body),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
}

/** Posts a meeting reminder when its alarm goes off. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(SystemNotifier.EXTRA_ID) ?: return
        SystemNotifier.post(context, id, intent.getStringExtra(SystemNotifier.EXTRA_TITLE).orEmpty(), intent.getStringExtra(SystemNotifier.EXTRA_BODY).orEmpty())
    }
}
