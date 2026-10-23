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
            revision: "51fc53c50a66779ca23d564168351da8ecd00faf"
        ),
        .package(
            url: "https://github.com/58opals/OpalDiagnostics.git",
            branch: "develop"
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
