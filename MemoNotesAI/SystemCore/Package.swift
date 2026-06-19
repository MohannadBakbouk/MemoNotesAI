// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SystemCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SystemCore", targets: ["SystemCore"]),
    ],
    dependencies: [
        .package(path: "../PersistenceCore"),
    ],
    targets: [
        .target(
            name: "SystemCore",
            dependencies: ["PersistenceCore"]
        ),
    ]
)
