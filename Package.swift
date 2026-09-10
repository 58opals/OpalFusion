// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "OpalFusion",
    platforms: [
        .macOS(.v27)
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
        )
    ],
    targets: [
        .target(
            name: "OpalFusion",
            dependencies: [
                .product(name: "OpalCrypto", package: "OpalCrypto"),
                .product(name: "OpalDiagnostics", package: "OpalDiagnostics")
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
