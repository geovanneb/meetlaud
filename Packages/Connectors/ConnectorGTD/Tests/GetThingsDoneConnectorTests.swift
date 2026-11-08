@testable import ConnectorGTD
import Connectors
import CryptoKit
import Foundation
import Testing

private func hex(_ text: String) -> Data {
    Data(stride(from: 0, to: text.count, by: 2).map { index in
        let start = text.index(text.startIndex, offsetBy: index)
        return UInt8(text[start ..< text.index(start, offsetBy: 2)], radix: 16) ?? 0
    })
}

/// The same values are in `server/tests/device-inbox.test.ts` in Get Things Done. If one side changes, the two stop
/// understanding each other, so a failure here means every paired phone just stopped working.
struct GTDCryptoVectorTests {
    private let phone = hex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
    private let computerPublic = hex("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f")
    private let phonePublic = hex("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")

    private func key() throws -> SymmetricKey {
        try GTDCrypto.sharedKey(
            privateKey: Curve25519.KeyAgreement.PrivateKey(rawRepresentation: phone), peer: computerPublic,
        )
    }

    @Test func `the key matches the one the computer derives`() throws {
        let bytes = try key().withUnsafeBytes { Data($0) }
        #expect(GTDCrypto.hex(bytes) == "7cee7972f23efd4c8d462c2a03c3c170cefd7094cd0411a86a93c6c65e388709")
    }

    @Test func `a seal matches, byte for byte`() throws {
        let sealed = try GTDCrypto.seal(
            Data("hello".utf8), key: key(), context: "place", nonce: AES.GCM.Nonce(data: Data(repeating: 7, count: 12)),
        )
        #expect(GTDCrypto.hex(sealed) == "07070707070707070707070785897688a7e84e27bd1d533096160e6075ed906289")
    }

    @Test func `a device id and a proof match`() {
        #expect(GTDCrypto.deviceID(publicKey: phonePublic) == "300c9c9603b92a4b39ed3958bf924011")
        #expect(GTDCrypto.hex(GTDCrypto.proof(code: Data(repeating: 9, count: 16), phonePublic))
            == "927e900179b981b9c691e9d014b41c9aa436f1d1116d3e39c2823fc89615434c")
    }

    @Test func `a seal is bound to its place, and any change is refused`() throws {
        let key = try key()
        let sealed = try GTDCrypto.seal(Data("words".utf8), key: key, context: "/v1/offer")
        #expect(throws: (any Error).self) { try GTDCrypto.open(sealed, key: key, context: "/v1/elsewhere") }
        var altered = sealed
        altered[14] ^= 1
        #expect(throws: (any Error).self) { try GTDCrypto.open(altered, key: key, context: "/v1/offer") }
        #expect(try GTDCrypto.open(sealed, key: key, context: "/v1/offer") == Data("words".utf8))
    }
}

struct GTDConnectorTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString) ?? .standard
    }

    @Test func `only audio is shared until the person says otherwise`() {
        #expect(GetThingsDoneConnector(defaults: defaults()).wantedContent == [.audio])
    }

    @Test func `transcripts and photos follow their switches`() {
        let defaults = defaults()
        defaults.set(true, forKey: GTDStore.transcriptsKey)
        #expect(GetThingsDoneConnector(defaults: defaults).wantedContent == [.audio, .transcript])
        defaults.set(true, forKey: GTDStore.photosKey)
        #expect(GetThingsDoneConnector(defaults: defaults).wantedContent == [.audio, .transcript, .photos])
    }

    @Test func `not linked, it sends nothing`() async {
        let connector = GetThingsDoneConnector(defaults: defaults())
        #expect(connector.linkedSince == nil)
        await #expect(throws: GTDError.notLinked) {
            try await connector.send(ConnectorPackage(id: UUID(), title: "Sync", date: .now))
        }
    }

    @Test func `it carries its own icon and summary`() throws {
        let manifest = GetThingsDoneConnector(defaults: defaults()).manifest
        #expect(manifest.summary.contains("Get Things Done"))
        guard case let .image(url) = manifest.icon else {
            Issue.record("The icon must come from the connector's bundle")
            return
        }
        #expect(try Data(contentsOf: url).count > 100)
    }

    @Test func `only local addresses are ever used`() throws {
        for host in ["10.0.0.2", "192.168.1.4", "172.20.10.3", "169.254.3.1", "127.0.0.1"] {
            #expect(GTDDiscovery.isLocal(host), "\(host)")
        }
        for host in ["8.8.8.8", "172.32.0.1", "example.com", "1.1.1.1", ""] {
            #expect(!GTDDiscovery.isLocal(host), "\(host)")
            #expect(throws: GTDError.notLocal) { try GTDDiscovery.url(host: host, port: 80) }
        }
    }

    @Test func `a QR from anything else is not a pairing code`() {
        #expect(throws: (any Error).self) { try GTDPairingCode(scanned: "https://example.com") }
        let wrongVersion = #"{"version":2,"name":"Mac","public_key":"AAAA","code":"AAAA","port":1,"hosts":[]}"#
        #expect(throws: (any Error).self) { try GTDPairingCode(scanned: wrongVersion) }
    }

    @Test func `a real pairing code reads`() throws {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        let secret = Data(repeating: 2, count: 16).base64EncodedString()
        let text = """
        {"version":1,"name":"Mac","public_key":"\(key)","code":"\(secret)","port":4000,"hosts":["192.168.1.2"],
        "expires_at":"2026-11-07T10:00:00.000Z"}
        """
        let code = try GTDPairingCode(scanned: text)
        #expect(code.name == "Mac")
        #expect(code.port == 4000)
    }

    @Test func `the day goes as the queue expects it`() {
        #expect(GetThingsDoneConnector.day(of: Date(timeIntervalSince1970: 1_793_750_400)).count == 10)
    }
}

struct GTDPairingFailureTests {
    @Test func `each failure says what to do about it`() {
        #expect(GTDPairingFailure(GTDError.wrongCode) == .expired)
        #expect(GTDPairingFailure(GTDError.wrongComputer) == .expired)
        #expect(GTDPairingFailure(URLError(.cannotConnectToHost)) == .unreachable)
        #expect(GTDPairingFailure(GTDError.notFound) == .unreachable)
    }

    @Test func `a QR from anything else is reported as that`() {
        #expect(throws: DecodingError.self) { try GTDPairingCode(scanned: "{}") }
    }
}

/// Runs against the real inbox from Get Things Done, when `GTD_PAIRING_FILE` points at a live pairing code.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GTD_PAIRING_FILE"] != nil))
struct GTDInteroperabilityTests {
    @Test func `a meeting reaches the real inbox`() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["GTD_PAIRING_FILE"])
        let code = try GTDPairingCode(scanned: String(contentsOfFile: path, encoding: .utf8))
        let base = try GTDDiscovery.url(host: "127.0.0.1", port: code.port)
        let identity = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = identity.publicKey.rawRepresentation
        try await GTDClient.pair(base: base, code: code, publicKey: publicKey, name: "Interop iPhone")

        let client = try GTDClient(
            base: base,
            deviceID: GTDCrypto.deviceID(publicKey: publicKey),
            key: GTDCrypto.sharedKey(privateKey: identity, peer: code.publicKey),
        )
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let audio = folder.appending(path: "recording.wav")
        // Larger than one chunk, so that the upload loop is what gets tested.
        try Self.wav(seconds: 40).write(to: audio)
        let transcript = folder.appending(path: "transcript.vtt")
        try Data("WEBVTT\n\n00:00:01.000 --> 00:00:04.000\nHello from the phone\n".utf8).write(to: transcript)

        let package = ConnectorPackage(id: UUID(), title: "Interop meeting", date: .now)
        let files = [
            GTDClient.Outgoing(name: "recording.wav", url: audio),
            GTDClient.Outgoing(name: "transcript.vtt", url: transcript),
        ]
        try await client.deliver(package, files: files, day: "2026-11-07")
        // A delivered meeting is not a second one.
        try await client.deliver(package, files: files, day: "2026-11-07")
    }

    private static func wav(seconds: Int) -> Data {
        let size = UInt32(16000 * 2 * seconds)
        func bytes(_ value: some FixedWidthInteger) -> Data {
            withUnsafeBytes(of: value.littleEndian) { Data($0) }
        }
        var data = Data("RIFF".utf8) + bytes(36 + size) + Data("WAVEfmt ".utf8) + bytes(UInt32(16))
        data += bytes(UInt16(1)) + bytes(UInt16(1)) + bytes(UInt32(16000)) + bytes(UInt32(32000))
        data += bytes(UInt16(2)) + bytes(UInt16(16)) + Data("data".utf8) + bytes(size)
        return data + Data(count: Int(size))
    }
}
