package com.meetlaud.app.infra.modeldelivery

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import com.meetlaud.app.infra.system.ForegroundWork
import com.meetlaud.app.infra.system.WorkKind
import com.meetlaud.domain.InstallFailure
import com.meetlaud.domain.InstallState
import com.meetlaud.domain.ModelDescriptor
import com.meetlaud.domain.ModelFile
import com.meetlaud.domain.ModelInstaller
import com.meetlaud.domain.NetworkLogEntry
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.launch
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.time.Instant
import kotlin.coroutines.coroutineContext

/**
 * Downloads models. The only code in the app that touches the network, as ModelDownloader.swift (D-004).
 *
 * Files land in a staging folder, each is verified, and the whole folder moves into place at the end. Engines can
 * never see a partial model. A foreground service keeps it going with the screen off, and a cut connection resumes
 * from the bytes already on disk.
 */
class ModelDownloader(
    context: Context,
    private val root: File,
    catalog: List<ModelDescriptor>,
    private val freeBytes: () -> Long,
    private val log: suspend (NetworkLogEntry) -> Unit,
) : ModelInstaller {
    private companion object {
        /** Room for the engine to open the model, on top of the download. */
        const val SPACE_MARGIN = 300_000_000L
        const val COMPLETE_MARKER = ".complete"
        /** Present while a model is wanted, so a download the system stopped picks up at the next launch. */
        const val WANTED_MARKER = ".wanted"
        const val RETRIES_AFTER_DAMAGE = 1
        const val BUFFER = 256 * 1024
    }

    private val catalog = catalog.associateBy { it.id }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val states = HashMap<String, InstallState>()
    private val jobs = HashMap<String, Job>()
    private val waiting = HashMap<String, ModelDescriptor>()
    private val eventFlow = MutableSharedFlow<Pair<String, InstallState>>(extraBufferCapacity = 64, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    override val events: Flow<Pair<String, InstallState>> = eventFlow

    init {
        File(root, ".staging").mkdirs()
        // Wi-Fi back: whatever waited for it starts again.
        runCatching {
            connectivity.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                    if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)) return
                    val ready = synchronized(this@ModelDownloader) { waiting.values.toList().also { waiting.clear() } }
                    ready.forEach { model -> scope.launch { install(model, allowsCellular = false) } }
                }
            })
        }
    }

    private fun staging(id: String) = File(File(root, ".staging"), id)
    private fun installed(id: String) = File(root, id)

    // MARK: - ModelInstaller

    override fun folder(id: String): File? = installed(id).takeIf { File(it, COMPLETE_MARKER).exists() }

    override suspend fun installedIDs(): Set<String> = catalog.keys.filter { folder(it) != null }.toSet()

    override suspend fun state(id: String): InstallState =
        if (folder(id) != null) InstallState.Ready else synchronized(this) { states[id] } ?: InstallState.NotInstalled

    override suspend fun install(model: ModelDescriptor, allowsCellular: Boolean) {
        if (folder(model.id) != null) return update(model.id, InstallState.Ready)
        // Claimed before anything else, so two calls at once can never run two jobs over the same folder.
        val job = scope.launch(start = CoroutineStart.LAZY) { run(model) }
        synchronized(this) {
            if (jobs[model.id]?.isActive == true) return
            jobs[model.id] = job
        }
        job.invokeOnCompletion { synchronized(this) { if (jobs[model.id] === job) jobs.remove(model.id) } }
        fun giveUp(state: InstallState) {
            job.cancel()
            update(model.id, state)
        }
        if (freeBytes() < model.totalBytes - stagedBytes(model) + SPACE_MARGIN) return giveUp(InstallState.Failed(InstallFailure.NO_SPACE))
        val folder = staging(model.id)
        if (!folder.mkdirs() && !folder.isDirectory) return giveUp(InstallState.Failed(InstallFailure.UNAVAILABLE))
        File(folder, WANTED_MARKER).writeText(if (allowsCellular) "cellular" else "wifi")
        // Everything already on disk needs no network: only checking and moving into place remain.
        val needsNetwork = model.files.any { !isStaged(model, it) }
        if (needsNetwork && !allowsCellular && isMetered()) {
            synchronized(this) { waiting[model.id] = model }
            return giveUp(InstallState.WaitingForWiFi)
        }
        update(model.id, if (stagedBytes(model) > 0) InstallState.Downloading(stagedBytes(model), model.totalBytes) else InstallState.Queued)
        job.start()
    }

    override suspend fun pause(id: String) {
        stop(id)
        val model = catalog[id] ?: return
        update(id, InstallState.Paused(stagedBytes(model), model.totalBytes))
    }

    override suspend fun cancel(id: String) {
        stop(id)
        staging(id).deleteRecursively()
        update(id, InstallState.NotInstalled)
    }

    override suspend fun remove(id: String) {
        cancel(id)
        installed(id).deleteRecursively()
        update(id, InstallState.NotInstalled)
    }

    /** Android cannot download with the app gone, as iOS can, so a model that was on its way starts again here. */
    override suspend fun reconnect() {
        val folders = File(root, ".staging").listFiles().orEmpty()
        for (folder in folders) {
            val model = catalog[folder.name] ?: continue
            val wanted = File(folder, WANTED_MARKER)
            if (wanted.exists()) install(model, wanted.readText() == "cellular")
            else update(model.id, InstallState.Paused(stagedBytes(model), model.totalBytes))
        }
    }

    // MARK: - Downloading

    private suspend fun stop(id: String) {
        val job = synchronized(this) {
            waiting.remove(id)
            jobs.remove(id)
        }
        File(staging(id), WANTED_MARKER).delete()
        job?.cancel()
        job?.join()
    }

    private fun isMetered(): Boolean {
        val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork) ?: return false
        return !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
    }

    private suspend fun run(model: ModelDescriptor) {
        val key = "download.${model.id}"
        ForegroundWork.hold(key, model.displayName, kind = WorkKind.TRANSFER)
        try {
            var retries = 0
            while (true) {
                for (file in model.files) {
                    if (!isStaged(model, file)) fetch(model, file)
                }
                update(model.id, InstallState.Verifying)
                val damaged = model.files.firstOrNull { sha256(File(staging(model.id), it.path)) != it.sha256 }
                if (damaged == null) break
                File(staging(model.id), damaged.path).delete()
                if (++retries > RETRIES_AFTER_DAMAGE) {
                    staging(model.id).deleteRecursively()
                    return update(model.id, InstallState.Failed(InstallFailure.DAMAGED))
                }
            }
            File(staging(model.id), WANTED_MARKER).delete()
            installed(model.id).deleteRecursively()
            if (!staging(model.id).renameTo(installed(model.id))) return update(model.id, InstallState.Failed(InstallFailure.UNAVAILABLE))
            File(installed(model.id), COMPLETE_MARKER).createNewFile()
            log(NetworkLogEntry(host = model.sourceHost, modelID = model.id, bytes = model.totalBytes, date = Instant.now()))
            update(model.id, InstallState.Ready)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: HttpStatusException) {
            android.util.Log.w("ModelDownloader", "${model.id}: ${error.message}")
            update(model.id, InstallState.Failed(InstallFailure.UNAVAILABLE))
        } catch (error: IOException) {
            android.util.Log.w("ModelDownloader", "${model.id}: paused by ${error.javaClass.simpleName}: ${error.message}")
            // A cut connection: the bytes so far stay, and the next try picks up from them.
            update(model.id, InstallState.Paused(stagedBytes(model), model.totalBytes))
        } finally {
            ForegroundWork.release(key)
        }
    }

    private class HttpStatusException(code: Int) : IOException("HTTP $code")

    /** Appends to what is already on disk, with a Range request, so a pause or a cut costs nothing. */
    private suspend fun fetch(model: ModelDescriptor, file: ModelFile) {
        val target = File(staging(model.id), file.path).apply { parentFile?.mkdirs() }
        var have = if (target.exists()) target.length() else 0L
        if (have > file.size) {
            target.delete()
            have = 0
        }
        val connection = URL(file.url).openConnection() as HttpURLConnection
        connection.connectTimeout = 30_000
        connection.readTimeout = 60_000
        connection.instanceFollowRedirects = true
        if (have > 0) connection.setRequestProperty("Range", "bytes=$have-")
        try {
            val code = connection.responseCode
            if (code == HttpURLConnection.HTTP_OK) have = 0 else if (code != HttpURLConnection.HTTP_PARTIAL) throw HttpStatusException(code)
            RandomAccessFile(target, "rw").use { output ->
                output.setLength(have)
                output.seek(have)
                connection.inputStream.use { input ->
                    val buffer = ByteArray(BUFFER)
                    var lastReport = 0L
                    while (true) {
                        coroutineContext.ensureActive()
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        have += read
                        val now = System.currentTimeMillis()
                        if (now - lastReport > 250) {
                            lastReport = now
                            val received = minOf(stagedBytes(model, except = file) + have, model.totalBytes)
                            update(model.id, InstallState.Downloading(received, model.totalBytes))
                            ForegroundWork.hold("download.${model.id}", model.displayName, received.toDouble() / maxOf(model.totalBytes, 1), WorkKind.TRANSFER)
                        }
                    }
                }
            }
            if (have != file.size) throw IOException("Short file")
        } finally {
            connection.disconnect()
        }
    }

    private fun isStaged(model: ModelDescriptor, file: ModelFile): Boolean = File(staging(model.id), file.path).length() == file.size

    /** Bytes already on disk, whole files and partial ones alike. */
    private fun stagedBytes(model: ModelDescriptor, except: ModelFile? = null): Long =
        model.files.filter { it != except }.sumOf { minOf(File(staging(model.id), it.path).length(), it.size) }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(1 shl 20)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun update(id: String, state: InstallState) {
        synchronized(this) { states[id] = state }
        eventFlow.tryEmit(id to state)
    }

}
