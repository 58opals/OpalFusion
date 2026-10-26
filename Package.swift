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
        ),
        .library(
            name: "OpalFusionCore",
            targets: ["OpalFusionCore"]
        ),
        .library(
            name: "CashFusionEngine",
            targets: ["CashFusionEngine"]
        ),
        .library(
            name: "MosaicEngine",
            targets: ["MosaicEngine"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/58opals/OpalCrypto.git",
            revision: "aefcf6a7d04d833bbb0e3db87d88809e0b6d234b"
        ),
        .package(
            url: "https://github.com/58opals/OpalDiagnostics.git",
            revision: "aa56dec5d6c8581beb2b3cef43b03dd577ccd9f1"
        )
    ],
    targets: [
        .target(
            name: "OpalFusionCore",
            dependencies: [
                .product(name: "OpalCrypto", package: "OpalCrypto"),
                .product(name: "OpalDiagnostics", package: "OpalDiagnostics")
            ]
        ),
        .target(
            name: "CashFusionEngine",
            dependencies: [
                "OpalFusionCore",
                .product(name: "OpalCrypto", package: "OpalCrypto"),
                .product(name: "OpalDiagnostics", package: "OpalDiagnostics")
            ]
        ),
        .target(
            name: "MosaicEngine",
            dependencies: [
                "OpalFusionCore",
                .product(name: "OpalCrypto", package: "OpalCrypto"),
                .product(name: "OpalDiagnostics", package: "OpalDiagnostics")
            ]
        ),
        .target(
            name: "OpalFusion",
            dependencies: ["OpalFusionCore", "CashFusionEngine", "MosaicEngine"]
        )
    ]
)
