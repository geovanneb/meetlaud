package com.meetlaud.app.infra.diarization

import kotlin.math.roundToInt
import kotlin.math.sqrt

/** Who is active in each frame of one 10-second window: one byte per frame and local speaker, 0 or 1. */
class WindowActivity(val startSample: Long, val activity: ByteArray) {
    fun isActive(frame: Int, speaker: Int): Boolean = activity[frame * LOCAL_SPEAKERS + speaker].toInt() != 0

    companion object {
        const val FRAMES = 589
        const val LOCAL_SPEAKERS = 3
    }
}

/** A voice heard in one window, and its unit-length print. */
class LocalVoice(val window: Int, val speaker: Int, val vector: FloatArray)

/** One stretch of one voice, in seconds. */
data class ClusterTurn(val cluster: Int, val start: Double, val end: Double)

/**
 * Groups the voices of every window into people, and lays them back on the meeting's timeline, as pyannote 3.1 does
 * with this embedding model: centroid linkage, and too-small groups folded into the closest large one.
 */
object SpeakerClustering {
    /** Euclidean distance between unit vectors, pyannote's own setting for WeSpeaker ResNet34. */
    const val THRESHOLD = 0.7045f

    /** A label per voice. With `count`, exactly that many groups when there are enough voices. */
    fun cluster(voices: List<FloatArray>, count: Int? = null): IntArray {
        val n = voices.size
        if (n == 0) return IntArray(0)
        val dimensions = voices[0].size
        val sums = Array(n) { voices[it].copyOf() }
        val members = Array(n) { mutableListOf(it) }
        val alive = BooleanArray(n) { true }
        var clusters = n
        val unit = Array(n) { normalized(sums[it]) }
        // Each group remembers its nearest neighbor, so a merge only updates what it touched.
        val nearest = IntArray(n) { -1 }
        val distance = FloatArray(n) { Float.MAX_VALUE }
        fun findNearest(i: Int) {
            nearest[i] = -1
            distance[i] = Float.MAX_VALUE
            for (j in 0 until n) {
                if (j == i || !alive[j]) continue
                val d = euclidean(unit[i], unit[j])
                if (d < distance[i]) {
                    distance[i] = d
                    nearest[i] = j
                }
            }
        }
        for (i in 0 until n) findNearest(i)
        val target = count?.coerceAtLeast(1) ?: 1
        while (clusters > target) {
            var a = -1
            for (i in 0 until n) if (alive[i] && nearest[i] >= 0 && (a < 0 || distance[i] < distance[a])) a = i
            if (a < 0) break
            if (count == null && distance[a] > THRESHOLD) break
            val b = nearest[a]
            for (k in 0 until dimensions) sums[a][k] += sums[b][k]
            members[a].addAll(members[b])
            alive[b] = false
            clusters -= 1
            unit[a] = normalized(sums[a])
            findNearest(a)
            for (i in 0 until n) {
                if (!alive[i] || i == a) continue
                if (nearest[i] == a || nearest[i] == b) findNearest(i)
                else {
                    val d = euclidean(unit[i], unit[a])
                    if (d < distance[i]) {
                        distance[i] = d
                        nearest[i] = a
                    }
                }
            }
        }
        var groups = (0 until n).filter { alive[it] }.map { members[it] }
        if (count == null) {
            // A group with too few voices is not a person. Its voices join the closest large group.
            val minimum = minOf(12, maxOf(2, n / 20))
            val large = groups.filter { it.size >= minimum }.ifEmpty { listOf(groups.maxBy { it.size }) }.map { it.toMutableList() }
            val centers = large.map { group -> normalized(sum(group.map { voices[it] }, dimensions)) }
            for (group in groups) {
                if (large.any { it === group } || group.size >= minimum) continue
                for (voice in group) {
                    val best = centers.indices.maxBy { dot(centers[it], voices[voice]) }
                    large[best].add(voice)
                }
            }
            groups = large
        }
        val labels = IntArray(n)
        // Numbered by first appearance, so the first person heard is the first speaker.
        groups.sortedBy { it.min() }.forEachIndexed { label, group -> group.forEach { labels[it] = label } }
        return labels
    }

    /**
     * Each frame gets as many voices as the windows heard there on average, the ones the windows heard most.
     * Stretches shorter than a quarter second are dropped.
     */
    fun reconstruct(windows: List<WindowActivity>, labels: Map<Long, Int>, clusters: Int, windowSamples: Int, sampleRate: Int, totalSamples: Long): List<ClusterTurn> {
        if (clusters == 0 || windows.isEmpty()) return emptyList()
        val hop = windowSamples.toDouble() / WindowActivity.FRAMES
        val total = (totalSamples / hop).toInt() + WindowActivity.FRAMES + 1
        val score = Array(total) { FloatArray(clusters) }
        val count = FloatArray(total)
        val cover = IntArray(total)
        windows.forEachIndexed { index, window ->
            val offset = (window.startSample / hop).roundToInt()
            for (frame in 0 until WindowActivity.FRAMES) {
                val t = offset + frame
                if (t >= total) break
                cover[t] += 1
                for (speaker in 0 until WindowActivity.LOCAL_SPEAKERS) {
                    if (!window.isActive(frame, speaker)) continue
                    count[t] += 1f
                    labels[key(index, speaker)]?.let { score[t][it] += 1f }
                }
            }
        }
        val active = Array(clusters) { BooleanArray(total) }
        for (t in 0 until total) {
            val speakers = if (cover[t] == 0) 0 else (count[t] / cover[t]).roundToInt()
            if (speakers == 0) continue
            score[t].indices.sortedByDescending { score[t][it] }.take(speakers).forEach { if (score[t][it] > 0) active[it][t] = true }
        }
        val turns = mutableListOf<ClusterTurn>()
        val end = totalSamples.toDouble() / sampleRate
        for (cluster in 0 until clusters) {
            var t = 0
            while (t < total) {
                if (!active[cluster][t]) {
                    t++
                    continue
                }
                var u = t
                while (u < total && active[cluster][u]) u++
                val start = t * hop / sampleRate
                val stop = minOf(u * hop / sampleRate, end)
                if (stop - start > 0.25) turns += ClusterTurn(cluster, start, stop)
                t = u
            }
        }
        return turns.sortedBy { it.start }
    }

    fun key(window: Int, speaker: Int): Long = window.toLong() * WindowActivity.LOCAL_SPEAKERS + speaker

    fun normalized(vector: FloatArray): FloatArray {
        var norm = 0.0
        for (value in vector) norm += value * value
        val scale = if (norm > 0) (1 / sqrt(norm)).toFloat() else 0f
        return FloatArray(vector.size) { vector[it] * scale }
    }

    private fun sum(vectors: List<FloatArray>, dimensions: Int): FloatArray {
        val total = FloatArray(dimensions)
        for (vector in vectors) for (k in 0 until dimensions) total[k] += vector[k]
        return total
    }

    private fun dot(a: FloatArray, b: FloatArray): Float {
        var total = 0f
        for (k in a.indices) total += a[k] * b[k]
        return total
    }

    private fun euclidean(a: FloatArray, b: FloatArray): Float {
        var total = 0f
        for (k in a.indices) {
            val d = a[k] - b[k]
            total += d * d
        }
        return sqrt(total)
    }
}
