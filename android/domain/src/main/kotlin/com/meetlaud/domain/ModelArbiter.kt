package com.meetlaud.domain

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds

/** Something else is using a model right now. */
class ModelBusyException : Exception("busy")

/**
 * Gives one piece of work at a time the right to load and run a heavy model. Engines are shared, and two models at
 * once is how the system ends up killing the app.
 */
class ModelArbiter {
    private val lock = Mutex()
    private var isHeld = false
    private val waiting = ArrayDeque<CompletableDeferred<Unit>>()

    /** Waits for its turn. For work the person already asked for, such as a transcription. */
    suspend fun acquire() {
        val turn = lock.withLock {
            if (!isHeld) {
                isHeld = true
                return
            }
            CompletableDeferred<Unit>().also { waiting.addLast(it) }
        }
        turn.await()
    }

    /** Takes the turn only if it is free. For optional work, such as a speed test. */
    suspend fun tryAcquire(): Boolean = lock.withLock {
        if (isHeld) return false
        isHeld = true
        true
    }

    /** Waits for its turn, and gives up when the coroutine is cancelled. It never joins the line. */
    suspend fun acquireCancelable(checkingEvery: Duration = 250.milliseconds) {
        while (!tryAcquire()) delay(checkingEvery)
    }

    suspend fun release() {
        lock.withLock {
            if (waiting.isEmpty()) isHeld = false else waiting.removeFirst().complete(Unit)
        }
    }
}
