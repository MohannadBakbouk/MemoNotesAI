// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RecordingFeature",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "RecordingFeature", targets: ["RecordingFeature"]),
    ],
    dependencies: [
        .package(path: "../PersistenceCore"),
    ],
    targets: [
        .target(
            name: "RecordingFeature",
            dependencies: ["PersistenceCore"]
        ),
    ]
)
