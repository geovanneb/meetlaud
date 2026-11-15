// swift-tools-version: 6.2
import PackageDescription

/// Runs the app's real summary pipeline on a Mac, with the real model, over invented meetings.
/// `Sources/Domain`, `Sources/TestSupport`, and `Sources/LLMMLX` are links to the app's own sources, so this
/// measures exactly what ships. See README.md.
let package = Package(
    name: "SummaryEval",
    platforms: [.macOS(.v26)],
    dependencies: [
        // The same versions as Packages/Package.resolved.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.1.9"),
    ],
    targets: [
        .target(name: "Domain", path: "Sources/Domain"),
        .target(name: "TestSupport", dependencies: ["Domain"], path: "Sources/TestSupport"),
        .target(
            name: "LLMMLX",
            dependencies: [
                "Domain",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Sources/LLMMLX",
        ),
        .executableTarget(
            name: "SummaryEval",
            dependencies: ["Domain", "TestSupport", "LLMMLX"],
            path: "Sources/SummaryEval",
        ),
    ],
)
