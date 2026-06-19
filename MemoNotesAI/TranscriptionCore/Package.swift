// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TranscriptionCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "TranscriptionCore", targets: ["TranscriptionCore"]),
    ],
    dependencies: [
        .package(path: "../PersistenceCore"),
        .package(path: "../NetworkCore"),
        .package(path: "../AudioCore"),
        .package(path: "../SystemCore"),
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "TranscriptionCore",
            dependencies: [
                "PersistenceCore",
                "NetworkCore",
                "AudioCore",
                "SystemCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            resources: [
                .copy("Resources/openai_whisper-base.en")
            ]
        ),
    ]
)
