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
 * background task does. One service for all of it, showing the first piece of work that asked, and declaring the
 * kind of each piece of work running: Google Play checks that the declared type matches what the app does.
 */
class WorkService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!declare()) stopSelf()
        return START_NOT_STICKY
    }

    /**
     * Puts the service in the foreground with the types of the work running now. Called again when they change: a
     * running service may change its own types from the background, where starting it again is not allowed.
     */
    internal fun declare(): Boolean {
        val notification = ForegroundWork.notification(this) ?: return false
        return runCatching { startForeground(ForegroundWork.ID, notification, ForegroundWork.serviceType()) }.isSuccess
    }

    override fun onCreate() {
        super.onCreate()
        ForegroundWork.running = this
    }

    override fun onDestroy() {
        if (ForegroundWork.running === this) ForegroundWork.running = null
        super.onDestroy()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android's daily limit for this kind of work. The work itself pauses and resumes later, as on iOS.
        stopSelf()
    }
}

/** What a piece of long work does, which decides the foreground service type Android and Google Play see. */
enum class WorkKind {
    /** Turning a recording into text on the device. */
    PROCESSING,
    /** Moving files over the network: a model download. */
    TRANSFER,
}

/** Who needs the service right now, and what its notification says. */
object ForegroundWork {
    internal const val ID = 2
    private const val CHANNEL = "work"
    private data class Holder(val title: String, val progress: Double?, val kind: WorkKind)
    private val holders = LinkedHashMap<String, Holder>()
    /** Null until install, as in unit tests: the work then runs without a service. */
    private var context: Context? = null
    /** The service while it runs, to change its types without starting it again. */
    @Volatile internal var running: WorkService? = null

    fun install(context: Context) {
        this.context = context.applicationContext
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, L10n.Nav.home, NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false); setSound(null, null) })
    }

    @Synchronized
    fun hold(key: String, title: String, progress: Double? = null, kind: WorkKind = WorkKind.PROCESSING) {
        val isFirst = holders.isEmpty()
        val before = kinds()
        holders[key] = Holder(title, progress, kind)
        val context = context ?: return
        when {
            isFirst -> runCatching { ContextCompat.startForegroundService(context, Intent(context, WorkService::class.java)) }
            before != kinds() -> redeclare()
            else -> refresh()
        }
    }

    /** The running service declares the types of the work now running. */
    private fun redeclare() {
        val service = running ?: return
        ContextCompat.getMainExecutor(service).execute { service.declare() }
    }

    private fun kinds(): Set<WorkKind> = holders.values.mapTo(mutableSetOf()) { it.kind }

    /** The types of the work running now. */
    @Synchronized
    internal fun serviceType(): Int = serviceType(kinds(), Build.VERSION.SDK_INT)

    /**
     * Data sync for downloads. Media processing for transcription, from Android 15, which added that type; before, data
     * sync is the type that allows it.
     */
    internal fun serviceType(kinds: Set<WorkKind>, sdk: Int): Int = kinds.fold(0) { type, kind ->
        type or when (kind) {
            WorkKind.TRANSFER -> ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            WorkKind.PROCESSING -> if (sdk >= 35) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING else ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        }
    }.takeIf { it != 0 } ?: ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC

    @Synchronized
    fun release(key: String) {
        val before = kinds()
        if (holders.remove(key) == null) return
        val context = context ?: return
        when {
            holders.isEmpty() -> context.stopService(Intent(context, WorkService::class.java))
            before != kinds() -> redeclare()
            else -> refresh()
        }
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
