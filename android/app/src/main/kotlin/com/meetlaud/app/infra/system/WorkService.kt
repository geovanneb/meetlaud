package com.meetlaud.app.infra.system

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.meetlaud.app.MainActivity
import com.meetlaud.app.R
import com.meetlaud.app.localization.L10n
import com.meetlaud.domain.BackgroundWorkLease

/**
 * Keeps long work going with the screen off: a transcription, or a model download. Android stops a background app
 * within minutes, and a foreground service with its notification is the honest way to ask for more, as iOS's
 * background task does. One service for all of it, showing the first piece of work that asked.
 */
class WorkService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = ForegroundWork.notification(this) ?: run {
            stopSelf()
            return START_NOT_STICKY
        }
        // Processing on Android 15 and later, which is what transcription is. Data sync before, which allows it.
        val type = if (Build.VERSION.SDK_INT >= 35) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING else ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        runCatching { startForeground(ForegroundWork.ID, notification, type) }.onFailure { stopSelf() }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android's daily limit for this kind of work. The work itself pauses and resumes later, as on iOS.
        stopSelf()
    }
}

/** Who needs the service right now, and what its notification says. */
object ForegroundWork {
    internal const val ID = 2
    private const val CHANNEL = "work"
    private data class Holder(val title: String, val progress: Double?)
    private val holders = LinkedHashMap<String, Holder>()
    /** Null until install, as in unit tests: the work then runs without a service. */
    private var context: Context? = null

    fun install(context: Context) {
        this.context = context.applicationContext
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, L10n.Nav.home, NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false); setSound(null, null) })
    }

    @Synchronized
    fun hold(key: String, title: String, progress: Double? = null) {
        val isFirst = holders.isEmpty()
        holders[key] = Holder(title, progress)
        val context = context ?: return
        if (isFirst) {
            runCatching { ContextCompat.startForegroundService(context, Intent(context, WorkService::class.java)) }
        } else {
            refresh()
        }
    }

    @Synchronized
    fun release(key: String) {
        if (holders.remove(key) == null) return
        val context = context ?: return
        if (holders.isEmpty()) context.stopService(Intent(context, WorkService::class.java)) else refresh()
    }

    private fun refresh() {
        val context = context ?: return
        val notification = notification(context) ?: return
        runCatching { context.getSystemService(NotificationManager::class.java).notify(ID, notification) }
    }

    @Synchronized
    internal fun notification(context: Context): Notification? {
        val holder = holders.values.firstOrNull() ?: return null
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(holder.title)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .apply { if (holder.progress != null) setProgress(1000, (holder.progress * 1000).toInt(), false) else setProgress(0, 0, true) }
            .build()
    }
}

/** The transcription's hold on the service, as BackgroundTaskLease does on iOS. */
class WorkServiceLease : BackgroundWorkLease {
    private companion object { const val KEY = "transcription" }
    private var title = ""

    override suspend fun begin(title: String) {
        this.title = title
        ForegroundWork.hold(KEY, title)
    }

    override suspend fun update(progress: Double) = ForegroundWork.hold(KEY, title, progress)

    override suspend fun end() = ForegroundWork.release(KEY)
}
