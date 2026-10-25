// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "CashFusionValidation",
    platforms: [.macOS(.v27)],
    dependencies: [
        .package(name: "OpalFusion", path: "../.."),
        .package(url: "https://github.com/58opals/OpalCrypto.git", revision: "06f9edcbd5b44c869e6f81f3da1ea147add1d8cf"),
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
