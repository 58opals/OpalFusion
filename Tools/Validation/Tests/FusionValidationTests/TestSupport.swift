import Darwin
import Foundation
import Testing
@testable import FusionValidation

private final class TestBundleAnchor: NSObject {}

func productsDirectory() -> URL { Bundle(for: TestBundleAnchor.self).bundleURL.deletingLastPathComponent() }
func repositoryRoot() -> URL {
    var result = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { result.deleteLastPathComponent() }
    return result
}
func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}
func readJSON<T>(_ url: URL, as: T.Type) throws -> T {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? T)
}
func stopped(_ pid: pid_t) -> Bool {
    let end = monotonicTime() + 1
    while monotonicTime() < end {
        if kill(pid, 0) == -1 && errno == ESRCH { return true }
        usleep(20_000)
    }
    return false
}
func waitFor(_ url: URL) throws {
    let end = monotonicTime() + 5
    while !FileManager.default.fileExists(atPath: url.path) && monotonicTime() < end { usleep(20_000) }
    #expect(FileManager.default.fileExists(atPath: url.path))
}
func waitForExit(_ process: Process, within seconds: Double = 6) throws -> Int32 {
    let end = monotonicTime() + seconds
    while process.isRunning && monotonicTime() < end { usleep(20_000) }
    if process.isRunning { process.interrupt(); throw ValidationFailure("Owned test command did not exit") }
    process.waitUntilExit()
    return process.terminationStatus
}

final class RunnerFixture {
    let root: URL
    let sources: URL
    let calls: URL
    let discovery: URL
    var environment: [String: String]
    let listing: [String: [String]]
    var fixtureExecutable: URL { productsDirectory().appendingPathComponent("ValidationFixture") }
    var commandExecutable: URL { productsDirectory().appendingPathComponent("fusion-validation") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        sources = root.appendingPathComponent("Tests/Mosaic/Tests/MosaicEngineTests", isDirectory: true)
        calls = root.appendingPathComponent("calls.jsonl")
        discovery = root.appendingPathComponent("discovery.json")
        let cash = [clientSuite] + boundedSuites + ["LiveRuntimeDriverValidator", "ElectronCashInteropValidator", "CashFusionAdditionalValidator"]
        let mosaic = mosaicFastSuites + mosaicRSASuites + [mosaicMaterialSuite, "FusionFacadeScaffoldValidator", "MosaicPrivateAlphaRuntimeRecoveryValidator", "MosaicPrivateAlphaRuntimeSPIValidator", "MosaicPrivateAlphaTransportBootstrapValidator"]
        listing = ["CashFusionEngineTests": cash.map { "CashFusionEngineTests.\($0)/validate()" },
                   "MosaicEngineTests": mosaic.map { "MosaicEngineTests.\($0)/validate()" }
                    + ["MosaicEngineTests.MosaicRehearsalValidator/executeSixContributorConductor()", "MosaicEngineTests.MosaicRehearsalValidator/executeThroughExactCommit()"]]
        environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("OPALFUSION_SPM_") }
        environment["PATH"] = root.appendingPathComponent("bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        environment["RUNNER_CALLS"] = calls.path
        environment["RUNNER_DISCOVERY"] = discovery.path
        environment["OPALFUSION_EC_INTEROP"] = "1"
        try write("", to: calls)
        try JSONSerialization.data(withJSONObject: listing).write(to: discovery)
        for name in mosaicFastSuites + ["MosaicMainnetAlphaReservationCoordinatorDependencyValidator", "MosaicPrivateAlphaRuntimeRecoveryValidator", "MosaicPrivateAlphaTransportBootstrapValidator", "RFC9500RSATestKeyFixture"] {
            try write("// Guard fixture\n", to: sources.appendingPathComponent(name + ".swift"))
        }
        for target in [root.appendingPathComponent("bin/swift"), root.appendingPathComponent("bin/xcrun"),
                       root.appendingPathComponent("toolchain/usr/libexec/swift/pm/swiftpm-testing-helper")] {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: target, withDestinationURL: productsDirectory().appendingPathComponent("ValidationFixture"))
        }
        try write("Built test bundle fixture\n", to: root.appendingPathComponent("products/MosaicEngineTests.xctest/Contents/MacOS/MosaicEngineTests"))
        for name in ["Library/Frameworks", "usr/lib"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("Platform/Developer/" + name), withIntermediateDirectories: true)
        }
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func readCalls() throws -> [[String: Any]] {
        try String(contentsOf: calls, encoding: .utf8).split(separator: "\n").map {
            try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
    }
    func invoke(_ mode: String = "develop", focus: String? = nil, scenario: String = "", overrides: [String: String] = [:]) throws -> (code: Int32, calls: [[String: Any]], output: String) {
        try write("", to: calls)
        var args = ["--repo-root", root.path, "--mode", mode]
        if let focus { args += ["--focus", focus] }
        var env = environment.merging(overrides, uniquingKeysWith: { _, new in new })
        env["RUNNER_SCENARIO"] = scenario
        var output = ""
        let code = ValidationCommand.run(arguments: args, environment: env) { line, _ in output += line + "\n" }
        return (code, try readCalls(), output)
    }
    func direct(mode: String = "fast", scenario: String = "", buildBudget: Double = 300, postBudget: Double = 60) throws -> (code: Int32, calls: [[String: Any]], output: String) {
        try write("", to: calls)
        var output = ""
        let code = runLane(Options(repoRoot: root, mode: mode), environment: environment.merging(["RUNNER_SCENARIO": scenario], uniquingKeysWith: { _, new in new }), buildBudget: buildBudget, postBudget: postBudget) { line, _ in output += line + "\n" }
        return (code, try readCalls(), output)
    }
    func launchCommand(scenario: String, marker: URL) throws -> Process {
        let process = Process()
        process.executableURL = commandExecutable
        process.arguments = ["--repo-root", root.path, "--mode", "build"]
        process.environment = environment.merging(["RUNNER_SCENARIO": scenario, "OWNED_MARKER": marker.path], uniquingKeysWith: { _, new in new })
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }
}

func arguments(_ call: [String: Any]) -> [String] { call["arguments"] as? [String] ?? [] }
func phaseNames(_ calls: [[String: Any]]) -> [String] { calls.compactMap { $0["phase"] as? String } }
