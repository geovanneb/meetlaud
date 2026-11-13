@testable import Archive
import Domain
import Foundation
import Testing

struct ArchiveFramingTests {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    @Test func `trailing bytes after the sealed stream are rejected`() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try SealedWriter(url: url, password: "fictional password")
        try writer.write(Data([0, 0, 0, 0]))
        try writer.finish()
        let output = try FileHandle(forWritingTo: url)
        try output.seekToEnd()
        try output.write(contentsOf: Data([42]))
        try output.close()
        let reader = try SealedReader(url: url, password: "fictional password")
        defer { reader.close() }
        _ = try reader.read(4)
        #expect(throws: ArchiveError.damaged) { try reader.requireEnd() }
    }

    @Test func `an early terminator cannot hide unread authenticated data`() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try SealedWriter(url: url, password: "fictional password")
        try writer.write(Data(repeating: 0, count: SealedFormat.blockSize + 8))
        try writer.finish()
        let reader = try SealedReader(url: url, password: "fictional password")
        defer { reader.close() }
        _ = try reader.read(SealedFormat.blockSize)
        #expect(throws: ArchiveError.damaged) { try reader.requireEnd() }
    }

    @Test func `a missing final block is rejected even after a complete entry`() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try SealedWriter(url: url, password: "fictional password")
        try writer.write(Data(repeating: 0, count: SealedFormat.blockSize + 1))
        try writer.finish()
        let header = SealedFormat.magic.count + 4 + SealedFormat.saltSize + SealedFormat.nonceSize
        // A block has a five-byte frame, twelve-byte nonce, and sixteen-byte tag.
        let output = try FileHandle(forWritingTo: url)
        try output.truncate(atOffset: UInt64(header + 5 + SealedFormat.blockSize + 28))
        try output.close()
        let reader = try SealedReader(url: url, password: "fictional password")
        defer { reader.close() }
        _ = try reader.read(SealedFormat.blockSize)
        #expect(throws: ArchiveError.damaged) { try reader.requireEnd() }
    }

    @Test func `a valid stream ends exactly after its payload`() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try SealedWriter(url: url, password: "fictional password")
        try writer.write(Data([0, 0, 0, 0]))
        try writer.finish()
        let reader = try SealedReader(url: url, password: "fictional password")
        defer { reader.close() }
        #expect(try reader.read(4) == Data([0, 0, 0, 0]))
        try reader.requireEnd()
    }
}
