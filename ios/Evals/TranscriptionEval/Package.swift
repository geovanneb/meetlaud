// swift-tools-version: 6.2
import PackageDescription

/// Links use the app's actual window reader, speech conditioning, and Whisper adapter.
let package = Package(
    name: "TranscriptionEval",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", exact: "0.18.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.1.9"),
    ],
    targets: [
        .target(name: "Domain", path: "Sources/Domain"),
        .target(name: "AudioEditing", dependencies: ["Domain"], path: "Sources/AudioEditing"),
        .target(
            name: "ASRWhisperKit",
            dependencies: ["Domain", .product(name: "WhisperKit", package: "argmax-oss-swift")],
            path: "Sources/ASRWhisperKit",
        ),
        .executableTarget(
            name: "TranscriptionEval", dependencies: ["Domain", "AudioEditing", "ASRWhisperKit"],
            path: "Sources/TranscriptionEval",
        ),
    ],
)
