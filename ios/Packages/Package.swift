// swift-tools-version: 6.2
import PackageDescription

/// The dependency graph below is the architecture. See docs/architecture.md.
/// Dependencies point inward: features and adapters know Domain, never each other.
let settings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .treatAllWarnings(as: .error),
]

func library(_ name: String) -> Product {
    .library(name: name, targets: [name])
}

func feature(_ name: String) -> Target {
    .target(
        name: name,
        dependencies: ["Domain", "AppRouting", "DesignSystem", "Localization", "FeatureShared"],
        path: "Features/\(name)/Sources",
        swiftSettings: settings,
    )
}

let package = Package(
    name: "MeetlaudKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26)],
    products: [
        library("Domain"),
        library("Connectors"),
        library("ConnectorGTD"),
        library("ConnectorsUI"),
        library("AppRouting"),
        library("Localization"),
        library("DesignSystem"),
        library("AppShell"),
        library("FeatureHome"),
        library("FeatureLibrary"),
        library("FeatureAsk"),
        library("FeatureTools"),
        library("FeatureSettings"),
        library("FeatureRecording"),
        library("FeatureDetail"),
        library("FeatureModels"),
        library("FeatureShared"),
        library("AudioCapture"),
        library("AudioPlayback"),
        library("Persistence"),
        library("Embeddings"),
        library("Archive"),
        library("AudioEditing"),
        library("SystemBridges"),
        library("ModelDelivery"),
        library("DeviceMonitoring"),
        library("ASRApple"),
        library("ASRWhisperKit"),
        library("DiarizationFluid"),
        library("LLMMLX"),
        library("FeaturePeople"),
        library("TestSupport"),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "0.9.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio", from: "0.17.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "3.32.3")),
        // Pinned to the range WhisperKit requires, since a package can only resolve to one version.
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMinor(from: "1.1.6")),
    ],
    targets: [
        // Core
        .target(name: "Domain", path: "Core/Domain/Sources", swiftSettings: settings),
        .target(
            name: "AppRouting",
            dependencies: ["Domain"],
            path: "Core/AppRouting/Sources",
            swiftSettings: settings,
        ),

        // UI
        .target(
            name: "Localization",
            path: "UI/Localization/Sources",
            resources: [.process("Resources")],
            swiftSettings: settings,
        ),
        .target(
            name: "DesignSystem",
            path: "UI/DesignSystem/Sources",
            resources: [.process("Resources")],
            swiftSettings: settings,
        ),
        .target(
            name: "AppShell",
            dependencies: ["AppRouting", "DesignSystem", "Localization"],
            path: "UI/AppShell/Sources",
            swiftSettings: settings,
        ),

        // Infrastructure
        .target(
            name: "AudioCapture",
            dependencies: ["Domain"],
            path: "Infrastructure/AudioCapture/Sources",
            swiftSettings: settings,
        ),
        .target(
            name: "AudioPlayback",
            dependencies: ["Domain"],
            path: "Infrastructure/AudioPlayback/Sources",
            swiftSettings: settings,
        ),
        .target(
            name: "Persistence",
            dependencies: ["Domain", .product(name: "GRDB", package: "GRDB.swift")],
            path: "Infrastructure/Persistence/Sources",
            swiftSettings: settings,
        ),

        .target(
            name: "AudioEditing",
            dependencies: ["Domain"],
            path: "Infrastructure/AudioEditing/Sources",
            swiftSettings: settings,
        ),
        .target(
            name: "SystemBridges",
            dependencies: ["Domain"],
            path: "Infrastructure/SystemBridges/Sources",
            swiftSettings: settings,
        ),

        .target(
            name: "ModelDelivery",
            dependencies: ["Domain"],
            path: "Infrastructure/ModelDelivery/Sources",
            resources: [.process("Resources")],
            swiftSettings: settings,
        ),
        .target(
            name: "DeviceMonitoring",
            dependencies: ["Domain"],
            path: "Infrastructure/DeviceMonitoring/Sources",
            swiftSettings: settings,
        ),
        .target(
            name: "ASRApple",
            dependencies: ["Domain"],
            path: "Infrastructure/ASRApple/Sources",
            swiftSettings: settings,
        ),
        .target(
            name: "ASRWhisperKit",
            dependencies: ["Domain", .product(name: "WhisperKit", package: "argmax-oss-swift")],
            path: "Infrastructure/ASRWhisperKit/Sources",
            swiftSettings: settings,
        ),

        .target(
            name: "DiarizationFluid",
            dependencies: ["Domain", .product(name: "FluidAudio", package: "FluidAudio")],
            path: "Infrastructure/DiarizationFluid/Sources",
            swiftSettings: settings,
        ),

        .target(
            name: "LLMMLX",
            dependencies: [
                "Domain",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Infrastructure/LLMMLX/Sources",
            swiftSettings: settings,
        ),

        .target(
            name: "Embeddings",
            dependencies: ["Domain"],
            path: "Infrastructure/Embeddings/Sources",
            swiftSettings: settings,
        ),

        .target(
            name: "Archive",
            dependencies: ["Domain"],
            path: "Infrastructure/Archive/Sources",
            swiftSettings: settings,
        ),

        // Features
        .target(
            name: "FeatureShared",
            dependencies: ["Domain", "DesignSystem", "Localization"],
            path: "Features/FeatureShared/Sources",
            swiftSettings: settings,
        ),
        feature("FeatureHome"),
        feature("FeatureLibrary"),
        feature("FeatureAsk"),
        .target(
            name: "FeatureTools",
            dependencies: [
                "Domain", "Connectors", "ConnectorsUI", "AppRouting", "DesignSystem", "Localization", "FeatureShared",
            ],
            path: "Features/FeatureTools/Sources",
            swiftSettings: settings,
        ),
        // Isolated on purpose: nothing of ours goes in, so a connector only sees what it is handed.
        .target(name: "Connectors", path: "Core/Connectors/Sources", swiftSettings: settings),
        .target(
            name: "ConnectorsUI",
            dependencies: ["Connectors"],
            path: "Connectors/ConnectorsUI/Sources",
            swiftSettings: settings,
        ),
        .target(
            name: "ConnectorGTD",
            dependencies: ["Connectors", "ConnectorsUI", "DesignSystem"],
            path: "Connectors/ConnectorGTD/Sources",
            resources: [.process("Resources")],
            swiftSettings: settings,
        ),
        feature("FeatureSettings"),
        feature("FeatureRecording"),
        feature("FeatureDetail"),
        feature("FeatureModels"),
        feature("FeaturePeople"),

        // Testing
        .target(
            name: "TestSupport",
            dependencies: ["Domain"],
            path: "Testing/TestSupport/Sources",
            swiftSettings: settings,
        ),

        // Tests
        .testTarget(
            name: "ConnectorGTDTests",
            dependencies: ["ConnectorGTD"],
            path: "Connectors/ConnectorGTD/Tests",
            swiftSettings: settings,
        ),
        .testTarget(
            name: "ConnectorsTests",
            dependencies: ["Connectors"],
            path: "Core/Connectors/Tests",
            swiftSettings: settings,
        ),
        .testTarget(
            name: "DomainTests",
            dependencies: ["Domain", "TestSupport"],
            path: "Core/Domain/Tests",
            swiftSettings: settings,
        ),
        .testTarget(
            name: "AudioCaptureTests",
            dependencies: ["AudioCapture"],
            path: "Infrastructure/AudioCapture/Tests",
            swiftSettings: settings,
        ),
        .testTarget(
            name: "AudioEditingTests",
            dependencies: ["AudioEditing", "Domain"],
            path: "Infrastructure/AudioEditing/Tests",
            swiftSettings: settings,
        ),
        .testTarget(
            name: "ModelDeliveryTests",
            dependencies: ["ModelDelivery"],
            path: "Infrastructure/ModelDelivery/Tests",
            swiftSettings: settings,
        ),
        .testTarget(
            name: "ASRWhisperKitTests",
            dependencies: ["ASRWhisperKit", "AudioEditing"],
            path: "Infrastructure/ASRWhisperKit/Tests",
            swiftSettings: settings,
        ),
        .testTarget(
            name: "DiarizationFluidTests",
            dependencies: ["DiarizationFluid", "AudioEditing"],
            path: "Infrastructure/DiarizationFluid/Tests",
            swiftSettings: settings,
        ),
        .testTarget(
            name: "ArchiveTests",
            dependencies: ["Archive", "Domain", "Persistence"],
            path: "Infrastructure/Archive/Tests",
            swiftSettings: settings,
        ),
        .testTarget(
            name: "EmbeddingsTests",
            dependencies: ["Embeddings", "Domain"],
            path: "Infrastructure/Embeddings/Tests",
            swiftSettings: settings,
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"],
            path: "Infrastructure/Persistence/Tests",
            swiftSettings: settings,
        ),
        .testTarget(
            name: "AppRoutingTests",
            dependencies: ["AppRouting"],
            path: "Core/AppRouting/Tests",
            swiftSettings: settings,
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"],
            path: "UI/DesignSystem/Tests",
            swiftSettings: settings,
        ),
        .testTarget(
            name: "LocalizationTests",
            dependencies: ["Localization"],
            path: "UI/Localization/Tests",
            swiftSettings: settings,
        ),
    ],
)
