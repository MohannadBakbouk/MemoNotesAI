// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SessionsFeature",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SessionsFeature", targets: ["SessionsFeature"]),
    ],
    dependencies: [
        .package(path: "../PersistenceCore"),
    ],
    targets: [
        .target(
            name: "SessionsFeature",
            dependencies: ["PersistenceCore"]
        ),
    ]
)
