// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "CashFusionValidation",
    platforms: [.macOS(.v27)],
    dependencies: [
        .package(name: "OpalFusion", path: "../.."),
        .package(url: "https://github.com/58opals/OpalCrypto.git", revision: "c0186d998040cea6380585a938be0d6299676d29"),
        .package(url: "https://github.com/58opals/OpalDiagnostics.git", revision: "393325d11591bf87c65288f7755337491b4b41b1")
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
