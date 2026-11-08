import Domain
import Foundation
import GRDB

extension DatabaseStore: DatabaseSnapshots {
    public func writeSnapshot(to url: URL, includingVoicePrints: Bool) async throws {
        let path = url.path
        try await database.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM INTO ?", arguments: [path])
        }
        guard !includingVoicePrints else { return }
        let copy = try DatabaseQueue(path: path)
        try await copy.writeWithoutTransaction { db in
            try db.inTransaction {
                try db.execute(sql: "DELETE FROM voicePrint")
                // A speaker's embedding identifies a voice just as much as a saved voice print does.
                try db.execute(sql: "UPDATE speaker SET embedding = NULL")
                return .commit
            }
            // Freed pages keep their old contents until this rewrites the file.
            try db.execute(sql: "VACUUM")
        }
        try copy.close()
    }

    public func restoreSnapshot(from url: URL) async throws {
        let source: DatabaseQueue
        do {
            source = try DatabaseQueue(path: url.path)
            let isNewer = try await source.read { try Self.migrator.hasBeenSuperseded($0) }
            guard !isNewer else { throw ArchiveError.incompatible }
            // An archive from an older version catches up here, before it touches the live data.
            try Self.migrator.migrate(source)
        } catch let error as ArchiveError {
            throw error
        } catch {
            throw ArchiveError.damaged
        }
        try source.backup(to: database)
        try source.close()
        try await database.write { try $0.notifyChanges(in: .fullDatabase) }
    }

    public func eraseEverything() async throws {
        try await database.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA secure_delete = ON")
            try db.inTransaction {
                // Cascades and search triggers take care of everything hanging from these.
                for table in [
                    "recording", "folder", "person", "conversation", "memory", "summaryTemplate", "roleSelection",
                    "modelRunStat", "networkLog",
                ] {
                    try db.execute(sql: "DELETE FROM \(table)")
                }
                return .commit
            }
            try db.execute(sql: "VACUUM")
        }
    }
}
