package com.meetlaud.app.infra.playback

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaMetadata
import android.media.MediaPlayer
import android.media.session.MediaSession
import android.media.session.PlaybackState
import com.meetlaud.domain.AudioPlaying
import java.io.File

/**
 * Plays a recording, and answers the lock screen and headphone controls, as SystemAudioPlayer.swift: back 15
 * seconds, forward 30, and the speed the person picked.
 */
class SystemAudioPlayer(private val context: Context) : AudioPlaying {
    private var player: MediaPlayer? = null
    private var session: MediaSession? = null
    private var title = ""

    override var rate: Float = 1f
        set(value) {
            field = value
            player?.let { applyRate(it) }
            publish()
        }

    override val duration: Double get() = (player?.duration ?: 0) / 1000.0
    override val currentTime: Double get() = (player?.currentPosition ?: 0) / 1000.0
    override val isPlaying: Boolean get() = runCatching { player?.isPlaying }.getOrNull() ?: false

    override fun load(file: File, title: String) {
        stop()
        if (!file.exists()) throw IllegalStateException("No audio")
        val created = MediaPlayer().apply {
            setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            setDataSource(file.path)
            prepare()
            setOnCompletionListener { publish() }
        }
        player = created
        this.title = title
        session = MediaSession(context, "meetlaud").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() = play()
                override fun onPause() = pause()
                override fun onRewind() = seek(currentTime - 15)
                override fun onFastForward() = seek(currentTime + 30)
                override fun onSeekTo(pos: Long) = seek(pos / 1000.0)
            })
            setMetadata(MediaMetadata.Builder().putString(MediaMetadata.METADATA_KEY_TITLE, title).putLong(MediaMetadata.METADATA_KEY_DURATION, created.duration.toLong()).build())
            isActive = true
        }
        publish()
    }

    private fun applyRate(player: MediaPlayer) {
        // Setting the speed of a paused player starts it, so a paused one waits until play.
        if (player.isPlaying) player.playbackParams = player.playbackParams.setSpeed(rate)
    }

    override fun play() {
        val player = player ?: return
        player.start()
        player.playbackParams = player.playbackParams.setSpeed(rate)
        publish()
    }

    override fun pause() {
        player?.takeIf { it.isPlaying }?.pause()
        publish()
    }

    override fun seek(time: Double) {
        val player = player ?: return
        player.seekTo((time.coerceIn(0.0, duration) * 1000).toLong(), MediaPlayer.SEEK_CLOSEST)
        publish()
    }

    override fun stop() {
        player?.release()
        player = null
        session?.release()
        session = null
    }

    private fun publish() {
        val session = session ?: return
        val state = if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
        session.setPlaybackState(
            PlaybackState.Builder()
                .setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_REWIND or PlaybackState.ACTION_FAST_FORWARD or PlaybackState.ACTION_SEEK_TO)
                .setState(state, (currentTime * 1000).toLong(), if (isPlaying) rate else 0f)
                .build(),
        )
    }
}
