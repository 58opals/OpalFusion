// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OpalFusion",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "OpalFusion",
            targets: ["OpalFusion"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/58opals/OpalCrypto.git",
            branch: "develop"
        ),
        .package(
            url: "https://github.com/58opals/OpalDiagnostics.git",
            branch: "develop"
        ),
        .package(
            url: "https://github.com/apple/swift-protobuf.git",
            branch: "main"
        )
    ],
    targets: [
        .target(
            name: "OpalFusion",
            dependencies: [
                .product(name: "OpalCrypto", package: "OpalCrypto"),
                .product(name: "OpalDiagnostics", package: "OpalDiagnostics"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ]
        ),
        .testTarget(
            name: "OpalFusionTests",
            dependencies: [
                "OpalFusion",
                .product(name: "OpalDiagnostics", package: "OpalDiagnostics")
            ]
        )
    ]
)
