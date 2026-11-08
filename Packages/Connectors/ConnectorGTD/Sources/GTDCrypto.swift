import CryptoKit
import Foundation

/// The sealing shared with Get Things Done. Changing anything here breaks every pairing: the fixed vectors in the
/// tests, on both sides, must keep matching.
enum GTDCrypto {
    private static let salt = Data("meetlaud-sync-v1".utf8)
    private static let info = Data("device-inbox-key".utf8)

    static func sharedKey(privateKey: Curve25519.KeyAgreement.PrivateKey, peer: Data) throws -> SymmetricKey {
        let secret = try privateKey.sharedSecretFromKeyAgreement(
            with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: peer),
        )
        return secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: info, outputByteCount: 32)
    }

    /// `context` binds a seal to one place, so that it cannot be replayed anywhere else.
    static func seal(_ plain: Data, key: SymmetricKey, context: String, nonce: AES.GCM.Nonce? = nil) throws -> Data {
        let box = try AES.GCM.seal(plain, using: key, nonce: nonce, authenticating: Data(context.utf8))
        guard let combined = box.combined else { throw GTDError.damagedAnswer }
        return combined
    }

    static func open(_ sealed: Data, key: SymmetricKey, context: String) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: Data(context.utf8))
    }

    static func deviceID(publicKey: Data) -> String {
        hex(SHA256.hash(data: publicKey)).prefix(32).description
    }

    static func proof(code: Data, _ parts: Data...) -> Data {
        var mac = HMAC<SHA256>(key: SymmetricKey(data: code))
        parts.forEach { mac.update(data: $0) }
        return Data(mac.finalize())
    }

    static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return hex(hash.finalize())
    }
}

enum GTDError: Error, Equatable {
    case notLinked, notFound, notLocal, wrongCode, wrongComputer, refused(Int), damagedAnswer
}
