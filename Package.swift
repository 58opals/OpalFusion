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
            revision: "0adfc220b30dfc9512bb8a45c1e4e6033e8bd95a"
        ),
        .package(
            url: "https://github.com/58opals/OpalDiagnostics.git",
            revision: "4147c6191a4d25624c4f4f7e4e97eaeb8010a8fd"
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
