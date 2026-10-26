// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MosaicValidation",
    platforms: [.macOS(.v27)],
    dependencies: [
        .package(name: "OpalFusion", path: "../.."),
        .package(url: "https://github.com/58opals/OpalCrypto.git", revision: "0adfc220b30dfc9512bb8a45c1e4e6033e8bd95a"),
        .package(url: "https://github.com/58opals/OpalDiagnostics.git", revision: "4147c6191a4d25624c4f4f7e4e97eaeb8010a8fd")
    ],
    targets: [
        .testTarget(
            name: "MosaicEngineTests",
            dependencies: [
                .product(name: "MosaicEngine", package: "OpalFusion"),
                .product(name: "OpalFusionCore", package: "OpalFusion"),
                .product(name: "OpalFusion", package: "OpalFusion"),
                .product(name: "OpalCrypto", package: "OpalCrypto"),
                .product(name: "OpalDiagnostics", package: "OpalDiagnostics")
            ]
        )
    ]
)
