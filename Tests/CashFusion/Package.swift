// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "CashFusionValidation",
    platforms: [.macOS(.v27)],
    dependencies: [
        .package(name: "OpalFusion", path: "../.."),
        .package(url: "https://github.com/58opals/OpalCrypto.git", revision: "aefcf6a7d04d833bbb0e3db87d88809e0b6d234b"),
        .package(url: "https://github.com/58opals/OpalDiagnostics.git", revision: "aa56dec5d6c8581beb2b3cef43b03dd577ccd9f1")
    ],
    targets: [
        .testTarget(
            name: "CashFusionEngineTests",
            dependencies: [
                .product(name: "CashFusionEngine", package: "OpalFusion"),
                .product(name: "OpalFusionCore", package: "OpalFusion"),
                .product(name: "OpalCrypto", package: "OpalCrypto"),
                .product(name: "OpalDiagnostics", package: "OpalDiagnostics")
            ]
        )
    ]
)
