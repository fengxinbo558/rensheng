// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SpeechSwiftMinimal",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "AudioCommon", targets: ["AudioCommon"]),
        .library(name: "CosyVoiceTTS", targets: ["CosyVoiceTTS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.30.0"),
    ],
    targets: [
        .target(
            name: "AudioCommon",
            dependencies: [],
            exclude: [
                "HuggingFaceDownloader.swift",
                "HuggingFaceRepoManifest.swift",
                "HuggingFaceTransfer.swift",
            ]
        ),
        .target(
            name: "MLXCommon",
            dependencies: [
                "AudioCommon",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift"),
            ]
        ),
        .target(
            name: "CosyVoiceTTS",
            dependencies: [
                "AudioCommon",
                "MLXCommon",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
