import CommonCrypto
import CryptoKit
import Domain
import Foundation

/// The file format: a clear header, then a sequence of sealed blocks.
///
/// Each block's nonce comes from its position, and its position and "last block" flag are authenticated. So blocks
/// cannot be reordered, removed, or cut off the end without the read failing. A block holds a fixed amount of plain
/// text, so a three-hour recording never has to fit in memory.
enum SealedFormat {
    static let magic = Data("MEETLAUD-ARCHIVE-1\n".utf8)
    static let blockSize = 1024 * 1024
    /// OWASP's figure for PBKDF2 with SHA-256. Slow on purpose: this is all that stands between a guess and a meeting.
    static let iterations: UInt32 = 600_000
    static let saltSize = 16
    static let nonceSize = 12

    static func key(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        var derived = Data(count: 32)
        let bytes = Array(password.utf8)
        let status = derived.withUnsafeMutableBytes { output in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password, bytes.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    output.bindMemory(to: UInt8.self).baseAddress, 32,
                )
            }
        }
        guard status == kCCSuccess else { throw ArchiveFailure.keyDerivation }
        return SymmetricKey(data: derived)
    }

    static func nonce(base: Data, counter: UInt64) throws -> AES.GCM.Nonce {
        var bytes = Array(base)
        for index in 0 ..< 8 {
            bytes[bytes.count - 1 - index] ^= UInt8((counter >> (UInt64(index) * 8)) & 0xFF)
        }
        return try AES.GCM.Nonce(data: bytes)
    }

    static func context(counter: UInt64, isLast: Bool) -> Data {
        withUnsafeBytes(of: counter.bigEndian) { Data($0) } + [isLast ? 1 : 0]
    }
}

enum ArchiveFailure: Error {
    case keyDerivation
}

/// Writes plain bytes in, sealed blocks out.
final class SealedWriter {
    private let handle: FileHandle
    private let key: SymmetricKey
    private let base: Data
    private var counter: UInt64 = 0
    private var pending = Data()

    init(url: URL, password: String) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        let salt = Data((0 ..< SealedFormat.saltSize).map { _ in UInt8.random(in: .min ... .max) })
        base = Data((0 ..< SealedFormat.nonceSize).map { _ in UInt8.random(in: .min ... .max) })
        key = try SealedFormat.key(password: password, salt: salt, iterations: SealedFormat.iterations)
        var header = SealedFormat.magic
        withUnsafeBytes(of: SealedFormat.iterations.bigEndian) { header.append(contentsOf: $0) }
        header.append(salt)
        header.append(base)
        try handle.write(contentsOf: header)
    }

    func write(_ data: Data) throws {
        pending.append(data)
        while pending.count > SealedFormat.blockSize {
            try seal(pending.prefix(SealedFormat.blockSize), isLast: false)
            pending = Data(pending.dropFirst(SealedFormat.blockSize))
        }
    }

    func finish() throws {
        try seal(pending, isLast: true)
        pending = Data()
        try handle.close()
    }

    private func seal(_ block: Data, isLast: Bool) throws {
        let box = try AES.GCM.seal(
            block,
            using: key,
            nonce: SealedFormat.nonce(base: base, counter: counter),
            authenticating: SealedFormat.context(counter: counter, isLast: isLast),
        )
        guard let combined = box.combined else { throw ArchiveError.damaged }
        var record = Data([isLast ? 1 : 0])
        withUnsafeBytes(of: UInt32(combined.count).bigEndian) { record.append(contentsOf: $0) }
        record.append(combined)
        try handle.write(contentsOf: record)
        counter += 1
    }
}

/// Reads sealed blocks in, plain bytes out. Only ever hands over text that passed authentication.
final class SealedReader {
    private let handle: FileHandle
    private let key: SymmetricKey
    private let base: Data
    private var counter: UInt64 = 0
    private var pending = Data()
    private var finished = false
    private(set) var bytesRead: UInt64 = 0

    init(url: URL, password: String) throws {
        handle = try FileHandle(forReadingFrom: url)
        let headerSize = SealedFormat.magic.count + 4 + SealedFormat.saltSize + SealedFormat.nonceSize
        guard let header = try handle.read(upToCount: headerSize), header.count == headerSize,
              header.prefix(SealedFormat.magic.count) == SealedFormat.magic
        else { throw ArchiveError.damaged }
        var offset = SealedFormat.magic.count
        let iterations = header[offset ..< offset + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        // A forged header must not be able to freeze the phone, or weaken the key to nothing.
        guard (100_000 ... 10_000_000).contains(iterations) else { throw ArchiveError.damaged }
        offset += 4
        let salt = header[offset ..< offset + SealedFormat.saltSize]
        offset += SealedFormat.saltSize
        base = Data(header[offset...])
        key = try SealedFormat.key(password: password, salt: Data(salt), iterations: iterations)
    }

    func close() {
        try? handle.close()
    }

    /// Exactly `count` bytes, or an error. Running out early means the file was cut.
    func read(_ count: Int) throws -> Data {
        while pending.count < count {
            guard try nextBlock() else { throw ArchiveError.damaged }
        }
        let result = Data(pending.prefix(count))
        pending = Data(pending.dropFirst(count))
        return result
    }

    /// The archive terminator is valid only at the authenticated end of the stream.
    func requireEnd() throws {
        guard pending.isEmpty else { throw ArchiveError.damaged }
        if !finished {
            _ = try nextBlock()
        }
        guard finished, pending.isEmpty,
              try handle.read(upToCount: 1)?.isEmpty != false
        else { throw ArchiveError.damaged }
    }

    private func nextBlock() throws -> Bool {
        guard !finished else { return false }
        guard let head = try handle.read(upToCount: 5), head.count == 5 else { throw ArchiveError.damaged }
        let start = head.startIndex
        guard head[start] <= 1 else { throw ArchiveError.damaged }
        let isLast = head[start] == 1
        let size = head[(start + 1)...].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard Int(size) <= SealedFormat.blockSize + 64,
              let body = try handle.read(upToCount: Int(size)), body.count == Int(size)
        else { throw ArchiveError.damaged }
        do {
            let box = try AES.GCM.SealedBox(combined: body)
            try pending.append(AES.GCM.open(
                box, using: key, authenticating: SealedFormat.context(counter: counter, isLast: isLast),
            ))
        } catch {
            // On the very first block a failure almost always means a mistyped password.
            throw counter == 0 ? ArchiveError.wrongPassword : ArchiveError.damaged
        }
        bytesRead += UInt64(size) + 5
        counter += 1
        finished = isLast
        return true
    }
}
