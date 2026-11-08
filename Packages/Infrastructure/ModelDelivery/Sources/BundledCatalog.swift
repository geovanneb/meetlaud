import Domain
import Foundation

/// The list of models, shipped inside the app. There is no server of ours to ask.
public struct BundledCatalog: ModelCatalog {
    public let models: [ModelDescriptor]

    private struct File: Decodable {
        let models: [ModelDescriptor]
    }

    public init() throws {
        guard let url = Bundle.module.url(forResource: "models", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        models = try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).models
    }
}
