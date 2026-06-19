// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PersistenceCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PersistenceCore", targets: ["PersistenceCore"]),
    ],
    targets: [
        .target(name: "PersistenceCore"),
    ]
)
