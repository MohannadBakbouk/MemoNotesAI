// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetworkCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "NetworkCore", targets: ["NetworkCore"]),
    ],
    targets: [
        .target(name: "NetworkCore"),
    ]
)
