// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "FusionValidation",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "fusion-validation", targets: ["FusionValidationCLI"])],
    targets: [
        .target(name: "FusionValidation"),
        .executableTarget(name: "FusionValidationCLI", dependencies: ["FusionValidation"]),
        .executableTarget(name: "ValidationFixture"),
        .testTarget(name: "FusionValidationTests", dependencies: ["FusionValidation", "FusionValidationCLI", "ValidationFixture"])
    ]
)
