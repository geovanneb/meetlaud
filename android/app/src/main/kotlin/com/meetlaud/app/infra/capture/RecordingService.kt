package com.meetlaud.app.infra.capture

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.meetlaud.app.MainActivity
import com.meetlaud.app.R
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.localization.Strings
import com.meetlaud.domain.CaptureStatus
import com.meetlaud.domain.PauseReason
import com.meetlaud.domain.RecordingActivityPresenter
import com.meetlaud.domain.TimeInterval
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Commands from outside the app's screens, as RecordingCommand in RecordingIntents.swift. They run in the app's process. */
enum class RecordingCommand { TOGGLE_PAUSE, STOP, MARK, START, TOGGLE, OPEN_LAST }

/**
 * Delivers commands to the app. A command can arrive before the app is ready, from a shortcut or a quick settings
 * tile that launched it, and it must not get lost.
 */
object RecordingCommandBridge {
    private val waiting = mutableListOf<RecordingCommand>()

    var handler: ((RecordingCommand) -> Unit)? = null
        set(value) {
            field = value
            if (value != null) {
                val commands = waiting.toList()
                waiting.clear()
                commands.forEach(value)
            }
        }

    fun send(command: RecordingCommand) {
        handler?.invoke(command) ?: waiting.add(command)
    }
}

/**
 * Keeps the microphone working with the screen off. Android requires a foreground service for that, and its ongoing
 * notification is the Live Activity of this app: the title, a clock that runs by itself, and Pause, Mark, and Stop.
 */
class RecordingService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.getStringExtra(COMMAND)?.let {
            RecordingCommandBridge.send(RecordingCommand.valueOf(it))
            return START_NOT_STICKY
        }
        val notification = state?.let { build(this, it) } ?: return START_NOT_STICKY
        startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        return START_NOT_STICKY
    }

    /** What the notification shows. Shared with the presenter, which updates it. */
    data class State(val title: String, val status: CaptureStatus, val recorded: TimeInterval, val since: Long)

    companion object {
        private const val ID = 1
        private const val CHANNEL = "recording"
        private const val COMMAND = "command"
        @Volatile internal var state: State? = null

        fun channel(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(CHANNEL, L10n.Recorder.statusRecording, NotificationManager.IMPORTANCE_LOW).apply {
                setShowBadge(false)
                setSound(null, null)
            }
            manager.createNotificationChannel(channel)
        }

        private fun action(context: Context, command: RecordingCommand, title: String): NotificationCompat.Action {
            val intent = Intent(context, RecordingService::class.java).putExtra(COMMAND, command.name)
            val pending = PendingIntent.getService(context, command.ordinal, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            return NotificationCompat.Action.Builder(0, title, pending).build()
        }

        internal fun build(context: Context, state: State): Notification {
            val open = PendingIntent.getActivity(
                context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE,
            )
            val phase = when (val status = state.status) {
                is CaptureStatus.Paused -> if (status.reason == PauseReason.USER) L10n.Recorder.statusPaused else L10n.Recorder.statusInterrupted
                CaptureStatus.Finishing -> L10n.Recorder.statusFinishing
                else -> L10n.Recorder.statusRecording
            }
            val running = state.status == CaptureStatus.Recording
            val builder = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(state.title)
                .setContentText(phase)
                .setContentIntent(open)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .setColor(ContextCompat.getColor(context, R.color.ds_record))
            if (running) {
                // The system runs the clock, as the Live Activity's timer does.
                builder.setUsesChronometer(true).setWhen(System.currentTimeMillis() - (state.recorded * 1000).toLong()).setShowWhen(true)
            }
            if (state.status != CaptureStatus.Finishing) {
                builder.addAction(action(context, RecordingCommand.TOGGLE_PAUSE, if (running) L10n.Recorder.pause else L10n.Recorder.resume))
                builder.addAction(action(context, RecordingCommand.MARK, L10n.Recorder.flag))
                builder.addAction(action(context, RecordingCommand.STOP, L10n.Recorder.stop))
            }
            return builder.build()
        }
    }
}

/**
 * Shows the recording outside the app, as LiveActivityPresenter.swift. If the person turned notifications off,
 * recording goes on without them: Android still shows the service in its list of running apps.
 */
class RecordingNotificationPresenter(private val context: Context) : RecordingActivityPresenter {
    init {
        RecordingService.channel(context)
    }

    override suspend fun begin(title: String) = withContext(Dispatchers.Main) {
        RecordingService.state = RecordingService.State(title, CaptureStatus.Recording, 0.0, SystemClock.elapsedRealtime())
        ContextCompat.startForegroundService(context, Intent(context, RecordingService::class.java))
    }

    override suspend fun update(status: CaptureStatus, recorded: TimeInterval) = withContext(Dispatchers.Main) {
        val state = RecordingService.state?.copy(status = status, recorded = recorded) ?: return@withContext
        RecordingService.state = state
        runCatching { context.getSystemService(NotificationManager::class.java).notify(1, RecordingService.build(context, state)) }
        Unit
    }

    override suspend fun end() = withContext(Dispatchers.Main) {
        RecordingService.state = null
        context.stopService(Intent(context, RecordingService::class.java))
        Unit
    }
}
