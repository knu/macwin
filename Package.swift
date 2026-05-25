// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "macwin",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "macwin", targets: ["macwin"])
    ],
    targets: [
        .executableTarget(name: "macwin")
    ]
)
