package com.meetlaud.app.infra.capture

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioRecordingConfiguration
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import com.meetlaud.domain.AudioCaptureEngine
import com.meetlaud.domain.AudioInput
import com.meetlaud.domain.CaptureEvent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.log10
import kotlin.math.sqrt

class CaptureException(message: String) : Exception(message)

/**
 * Captures the microphone with AudioRecord, straight at the segment format. The counterpart of
 * LiveCaptureEngine.swift. A reading thread writes every buffer to disk; pausing keeps the microphone open and drops
 * samples (D-029). When another app, such as the phone, takes the microphone, Android silences this one: that is
 * the interruption iOS reports, and it ends when the samples come back.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class LiveCaptureEngine(context: Context) : AudioCaptureEngine {
    private val audio = context.getSystemService(AudioManager::class.java)
    private val lane = Dispatchers.IO.limitedParallelism(1)
    private val signal = MutableSharedFlow<CaptureEvent>(extraBufferCapacity = 64, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    override val events: Flow<CaptureEvent> = signal

    private val lock = Object()
    private var record: AudioRecord? = null
    private var reader: Thread? = null
    private var writer: PcmSegmentWriter? = null
    @Volatile private var isPaused = false
    @Volatile private var isRunning = false
    @Volatile private var hasFailed = false
    @Volatile private var isSilenced = false
    private var preferred: AudioDeviceInfo? = null
    private val main = Handler(Looper.getMainLooper())

    private val silencing = object : AudioManager.AudioRecordingCallback() {
        override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>) {
            val session = record?.audioSessionId ?: return
            val mine = configs.firstOrNull { it.clientAudioSessionId == session } ?: return
            if (mine.isClientSilenced && !isSilenced) {
                isSilenced = true
                signal.tryEmit(CaptureEvent.InterruptionBegan)
            } else if (!mine.isClientSilenced && isSilenced) {
                isSilenced = false
                signal.tryEmit(CaptureEvent.InterruptionEnded(shouldResume = true))
            }
        }
    }

    @SuppressLint("MissingPermission")
    override suspend fun start(directory: File) = withContext(lane) {
        synchronized(lock) {
            writer = PcmSegmentWriter(directory)
            isPaused = false
            hasFailed = false
            isSilenced = false
        }
        startRecord()
        audio.registerAudioRecordingCallback(silencing, main)
    }

    @SuppressLint("MissingPermission")
    private fun startRecord() {
        val minimum = AudioRecord.getMinBufferSize(SegmentFormat.SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (minimum <= 0) throw CaptureException("No input")
        val created = AudioRecord.Builder()
            // Tuned for speech, with the processing a meeting wants and no voice-call echo games.
            .setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(SegmentFormat.SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build(),
            )
            .setBufferSizeInBytes(maxOf(minimum * 4, SegmentFormat.SAMPLE_RATE))
            .build()
        if (created.state != AudioRecord.STATE_INITIALIZED) {
            created.release()
            throw CaptureException("No input")
        }
        preferred?.let { created.preferredDevice = it }
        created.startRecording()
        record = created
        isRunning = true
        reader = Thread({ readLoop(created) }, "meetlaud-capture").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
    }

    private fun readLoop(source: AudioRecord) {
        val buffer = ShortArray(SegmentFormat.SAMPLE_RATE / 10)
        while (isRunning) {
            val count = source.read(buffer, 0, buffer.size)
            if (count <= 0) {
                if (count < 0 && isRunning) {
                    signal.tryEmit(CaptureEvent.Failed("read $count"))
                    return
                }
                continue
            }
            synchronized(lock) {
                val writer = writer ?: return
                if (isPaused || hasFailed || isSilenced) return@synchronized
                try {
                    writer.append(buffer, count)
                    signal.tryEmit(CaptureEvent.Progress(writer.framesWritten.toDouble() / SegmentFormat.SAMPLE_RATE, level(buffer, count)))
                } catch (error: Exception) {
                    // Usually a full disk. Stop writing and report, instead of failing again on every buffer.
                    hasFailed = true
                    signal.tryEmit(CaptureEvent.Failed(error.message ?: "write"))
                }
            }
        }
    }

    private fun stopRecord() {
        isRunning = false
        record?.let {
            runCatching { it.stop() }
            reader?.join(2000)
            it.release()
        }
        record = null
        reader = null
    }

    override suspend fun pause() {
        isPaused = true
    }

    override suspend fun resume() = withContext(lane) {
        if (record == null || record?.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            stopRecord()
            startRecord()
        }
        isSilenced = false
        isPaused = false
    }

    override suspend fun stop() = withContext(lane) {
        audio.unregisterAudioRecordingCallback(silencing)
        stopRecord()
        synchronized(lock) {
            writer?.close()
            writer = null
        }
    }

    /** Android releases the microphone with the recorder, so there is no session left to close. */
    override suspend fun deactivate() = Unit

    override suspend fun availableInputs(): List<AudioInput> =
        audio.getDevices(AudioManager.GET_DEVICES_INPUTS).map { AudioInput(it.id.toString(), it.productName?.toString()?.ifBlank { null } ?: typeName(it.type)) }

    override suspend fun selectInput(input: AudioInput) {
        val device = audio.getDevices(AudioManager.GET_DEVICES_INPUTS).firstOrNull { it.id.toString() == input.id }
        preferred = device
        record?.preferredDevice = device
    }

    private fun typeName(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Microphone"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Headset"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth"
        AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET -> "USB"
        else -> "Input"
    }

    companion object {
        /** Perceptual level from 0 to 1, for the waveform, the same curve as iOS: -55 dB to 0 dB. */
        fun level(buffer: ShortArray, count: Int): Float {
            if (count <= 0) return 0f
            var sum = 0.0
            for (index in 0 until count) {
                val value = buffer[index] / 32768.0
                sum += value * value
            }
            val rms = sqrt(sum / count)
            val decibels = 20 * log10(maxOf(rms, 0.000_01))
            return ((decibels + 55) / 55).coerceIn(0.0, 1.0).toFloat()
        }
    }
}
