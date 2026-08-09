// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EmotionCosyProbe",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "emotion-cosy-probe", targets: ["EmotionCosyProbe"]),
    ],
    dependencies: [
        .package(path: "../../../.emotion-runtime/speech-swift-minimal"),
    ],
    targets: [
        .executableTarget(
            name: "EmotionCosyProbe",
            dependencies: [
                .product(name: "AudioCommon", package: "speech-swift-minimal"),
                .product(name: "CosyVoiceTTS", package: "speech-swift-minimal"),
            ],
            path: "Sources"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
