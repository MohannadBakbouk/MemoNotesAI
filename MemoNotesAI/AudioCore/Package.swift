// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AudioCore", targets: ["AudioCore"]),
    ],
    dependencies: [
        .package(path: "../PersistenceCore"),
    ],
    targets: [
        .target(
            name: "AudioCore",
            dependencies: ["PersistenceCore"]
        ),
    ]
)
