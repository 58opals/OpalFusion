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
            revision: "cdd407d32d762ee77477914a142fa9700789e839"
        ),
        .package(
            url: "https://github.com/58opals/OpalDiagnostics.git",
            revision: "393325d11591bf87c65288f7755337491b4b41b1"
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
