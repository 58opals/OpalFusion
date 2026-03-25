// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OpalFusion",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .watchOS(.v26),
        .tvOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "OpalFusion",
            targets: ["OpalFusion"]
        )
    ],
    targets: [
        .target(
            name: "OpalFusion"
        )
    ]
)
