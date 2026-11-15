import Connectors
import CryptoKit
import Foundation

/// Speaks to the inbox on the computer. See `docs/device-inbox.md` in Get Things Done.
struct GTDClient {
    /// Well under the 2 MB the inbox takes, so that a slow hotspot makes progress between failures.
    static let chunkBytes = 1 << 20

    let base: URL
    let deviceID: String
    let key: SymmetricKey
    private let session: URLSession

    init(base: URL, deviceID: String, key: SymmetricKey) {
        self.base = base
        self.deviceID = deviceID
        self.key = key
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    private struct OfferedFile: Codable {
        let name: String
        let size: Int64
        let sha256: String
    }

    private struct OfferedItem: Codable {
        let id: String
        let title: String
        let date: String
        let files: [OfferedFile]
    }

    private struct Offer: Encodable {
        let items: [OfferedItem]
    }

    private struct StatusItem: Decodable {
        let complete: Bool
        let files: [Int64]
    }

    private struct Status: Decodable {
        let items: [StatusItem]
    }

    private struct Received: Decodable {
        let received: Int64
    }

    private struct Committed: Decodable {
        // swiftlint:disable:next identifier_name
        let meeting_id: String
    }

    /// One file that is about to travel.
    struct Outgoing {
        let name: String
        let url: URL
    }

    static func pair(base: URL, code: GTDPairingCode, publicKey: Data, name: String) async throws {
        var request = URLRequest(url: base.appending(path: "v1/pair"))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "phone_public": publicKey.base64EncodedString(),
            "phone_name": name,
            "proof": GTDCrypto.proof(code: code.code, publicKey).base64EncodedString(),
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw GTDError.wrongCode }
        let answer = try JSONDecoder().decode([String: Data].self, from: data)
        // Whoever answered must also hold the code, so that a stranger on the network cannot pose as the computer.
        guard answer["proof"] == GTDCrypto.proof(code: code.code, code.publicKey, publicKey) else {
            throw GTDError.wrongComputer
        }
    }

    func deliver(_ package: ConnectorPackage, files: [Outgoing], day: String) async throws {
        let id = package.id.uuidString.lowercased()
        var offered: [OfferedFile] = []
        for file in files {
            let size = try FileManager.default.attributesOfItem(atPath: file.url.path)[.size] as? Int64 ?? 0
            try offered.append(OfferedFile(name: file.name, size: size, sha256: GTDCrypto.sha256(of: file.url)))
        }
        let item = OfferedItem(id: id, title: package.title, date: day, files: offered)
        let status: Status = try await call("/v1/offer", Offer(items: [item]))
        guard let current = status.items.first else { throw GTDError.damagedAnswer }
        guard !current.complete else { return }
        for index in files.indices {
            try await upload(
                files[index].url,
                size: offered[index].size,
                id: id,
                index: index,
                from: current.files[index],
            )
        }
        let _: Committed = try await call("/v1/items/\(id)/commit", [String: String]())
    }

    private func upload(_ file: URL, size: Int64, id: String, index: Int, from start: Int64) async throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var offset = start
        while offset < size {
            try handle.seek(toOffset: UInt64(offset))
            guard let chunk = try handle.read(upToCount: Self.chunkBytes), !chunk.isEmpty else { break }
            let route = "/v1/items/\(id)/files/\(index)"
            let context = "\(route)?offset=\(offset)"
            guard let url = URL(string: context, relativeTo: base) else { throw GTDError.damagedAnswer }
            let answer: Received = try await exchange(
                url: url, method: "PUT", sealed: GTDCrypto.seal(chunk, key: key, context: context), route: route,
            )
            // The computer says what it holds, which may differ if an earlier answer was lost.
            offset = answer.received
        }
    }

    private func call<Answer: Decodable>(_ route: String, _ body: some Encodable) async throws -> Answer {
        guard let url = URL(string: route, relativeTo: base) else { throw GTDError.damagedAnswer }
        let plain = try JSONEncoder().encode(body)
        return try await exchange(
            url: url, method: "POST", sealed: GTDCrypto.seal(plain, key: key, context: route), route: route,
        )
    }

    private func exchange<Answer: Decodable>(
        url: URL,
        method: String,
        sealed: Data,
        route: String,
    ) async throws -> Answer {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(deviceID, forHTTPHeaderField: "X-Device")
        let (data, response) = try await session.upload(for: request, from: sealed)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw GTDError.refused(status) }
        return try JSONDecoder().decode(
            Answer.self, from: GTDCrypto.open(data, key: key, context: "answer:\(route)"),
        )
    }
}
