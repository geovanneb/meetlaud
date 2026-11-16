import CryptoKit
import Foundation
import Security

/// What a pairing code holds, as Get Things Done writes it.
struct GTDPairingCode: Decodable, Equatable {
    let version: Int
    let name: String
    let publicKey: Data
    let code: Data
    let port: Int
    let hosts: [String]

    private enum CodingKeys: String, CodingKey {
        case version, name, code, port, hosts
        case publicKey = "public_key"
    }

    /// A code from any other QR, or from a future version this app cannot speak, is simply not a code.
    init(scanned text: String) throws {
        self = try JSONDecoder().decode(Self.self, from: Data(text.utf8))
        guard version == 1, publicKey.count == 32, code.count == 16 else { throw GTDError.wrongCode }
    }
}

/// The computer this phone is linked to.
struct GTDLink: Codable, Equatable {
    var computerName: String
    var computerKey: Data
    var port: Int
    var hosts: [String]
    var linkedAt: Date

    var fingerprint: String {
        GTDCrypto.deviceID(publicKey: computerKey)
    }
}

/// Where the link and the choices live. The private key is in the Keychain, on this device only, and readable after
/// the first unlock so that delivery can finish with the screen locked.
struct GTDStore: @unchecked Sendable {
    /// Unchecked because UserDefaults is documented as safe across threads, and this holds no other state.
    let defaults: UserDefaults
    private static let account = "gtd.identity"
    private static let service = "com.meetlaud.connectors"
    private static let linkKey = "connectors.gtd.link"
    static let transcriptsKey = "connectors.gtd.transcripts"
    static let photosKey = "connectors.gtd.photos"

    var link: GTDLink? {
        defaults.data(forKey: Self.linkKey).flatMap { try? JSONDecoder().decode(GTDLink.self, from: $0) }
    }

    func save(_ link: GTDLink) {
        defaults.set(try? JSONEncoder().encode(link), forKey: Self.linkKey)
    }

    func forget() {
        defaults.removeObject(forKey: Self.linkKey)
        SecItemDelete(identityQuery as CFDictionary)
    }

    private var identityQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    func identity() throws -> Curve25519.KeyAgreement.PrivateKey {
        var query = identityQuery
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        var add = identityQuery
        add[kSecValueData as String] = key.rawRepresentation
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw GTDError.notLinked }
        return key
    }
}
