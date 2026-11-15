package com.meetlaud.connectors

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File
import java.time.Instant
import java.util.UUID

/**
 * The contract between Meetlaud and anything that can receive meeting material, as Connector.swift (D-067). This
 * package is the only thing a connector and the app share: a connector never sees the library, the database, or a
 * model, only the `ConnectorPackage` a person chose to send.
 */
interface Connector {
    val manifest: ConnectorManifest
    /** When this device was linked to the other app, or null if it is not. */
    val linkedSince: Instant? get() = null
    /** What the person agreed to share. Anything else never reaches the connector. */
    val wantedContent: Set<ConnectorContent> get() = emptySet()
    /** Fires when the other app may be reachable, so that delivery starts on its own. */
    fun peerChanges(): Flow<Unit> = emptyFlow()
    /** Receives one meeting. Must be safe to call again with the same meeting. */
    suspend fun send(pkg: ConnectorPackage)
}

/** What a connector can be given. */
enum class ConnectorContent { AUDIO, TRANSCRIPT, PHOTOS, NOTES }

data class ConnectorPackage(
    val id: UUID,
    val title: String,
    val date: Instant,
    val audioFile: File? = null,
    val transcript: String? = null,
    val photos: List<File> = emptyList(),
)

sealed interface ConnectorIcon {
    data class Symbol(val name: String) : ConnectorIcon
    /** An image the connector carries with it. */
    data class Image(val file: File) : ConnectorIcon
}

data class ConnectorManifest(
    val id: String,
    val name: String,
    /** A sentence or two on what the other app is, in the person's language. */
    val summary: String,
    val icon: ConnectorIcon,
    val category: Category,
    val transport: Transport,
    val accepts: Set<ConnectorContent>,
    val availability: Availability,
) {
    /** How data would travel. Local means the two devices talk directly, with no server in between. */
    enum class Transport { LOCAL_WIFI }

    enum class Category { PRODUCTIVITY }

    enum class Availability { AVAILABLE, COMING_SOON }
}

class ConnectorException(val reason: Reason) : Exception(reason.name) {
    enum class Reason { UNKNOWN_CONNECTOR, UNAVAILABLE }
}

/** The connectors in this build. The app fills it in one place, and everything else reads from it. */
class ConnectorRegistry(connectors: List<Connector> = emptyList()) {
    /** The first of two connectors with the same id wins: an id is what a saved choice would point at. */
    val connectors: List<Connector> = connectors.distinctBy { it.manifest.id }

    val manifests: List<ConnectorManifest> get() = connectors.map { it.manifest }

    /** Only categories with something in them, so that a screen never shows an empty heading. */
    val categories: List<ConnectorManifest.Category> get() = ConnectorManifest.Category.entries.filter { manifests(it).isNotEmpty() }

    fun manifests(category: ConnectorManifest.Category): List<ConnectorManifest> = manifests.filter { it.category == category }

    fun connector(id: String): Connector? = connectors.firstOrNull { it.manifest.id == id }

    suspend fun send(pkg: ConnectorPackage, id: String) = ready(id).send(pkg)

    private fun ready(id: String): Connector {
        val connector = connector(id) ?: throw ConnectorException(ConnectorException.Reason.UNKNOWN_CONNECTOR)
        if (connector.manifest.availability != ConnectorManifest.Availability.AVAILABLE) throw ConnectorException(ConnectorException.Reason.UNAVAILABLE)
        return connector
    }
}

/** A finished meeting, in the terms of this package. */
data class ConnectorMeeting(val id: UUID, val createdAt: Instant)

/** Where meetings come from. */
interface ConnectorMeetingSource {
    /** Finished meetings, not in the trash. */
    suspend fun finishedMeetings(): List<ConnectorMeeting>
    /** Only the content asked for. Null while the meeting is not ready to go, such as still being transcribed. */
    suspend fun pkg(id: UUID, including: Set<ConnectorContent>): ConnectorPackage?
    suspend fun logDelivery(pkg: ConnectorPackage, connector: ConnectorManifest)
}

/** What already went where. It is what makes sending again safe, and it survives the app closing. */
interface ConnectorDeliveryLog {
    fun isDelivered(meeting: UUID, connector: String): Boolean
    fun markDelivered(meeting: UUID, connector: String)
}

/**
 * Sends what is pending to each linked connector, one meeting at a time, as ConnectorSync.swift. The phone always
 * starts: nothing here waits for a request. A failure stops that connector until the next chance, and nothing is lost.
 */
class ConnectorSync(private val registry: ConnectorRegistry, private val source: ConnectorMeetingSource, private val log: ConnectorDeliveryLog) {
    private val lock = Mutex()
    private var isRunning = false
    private var runAgain = false

    /** A call during a run asks for one more, so that a meeting finished meanwhile is not left waiting. */
    suspend fun run() {
        lock.withLock {
            if (isRunning) {
                runAgain = true
                return
            }
            isRunning = true
        }
        do {
            lock.withLock { runAgain = false }
            for (connector in registry.connectors) {
                if (connector.manifest.availability == ConnectorManifest.Availability.AVAILABLE) deliver(connector)
            }
        } while (lock.withLock { runAgain })
        lock.withLock { isRunning = false }
    }

    private suspend fun deliver(connector: Connector) {
        // Only what was recorded after linking. Connecting must not send a whole history no one chose to send.
        val since = connector.linkedSince ?: return
        val id = connector.manifest.id
        val pending = source.finishedMeetings().filter { it.createdAt >= since && !log.isDelivered(it.id, id) }.sortedBy { it.createdAt }
        for (meeting in pending) {
            val pkg = source.pkg(meeting.id, connector.wantedContent) ?: continue
            try {
                connector.send(pkg)
            } catch (_: Exception) {
                return
            }
            log.markDelivered(meeting.id, id)
            source.logDelivery(pkg, connector.manifest)
        }
    }
}
