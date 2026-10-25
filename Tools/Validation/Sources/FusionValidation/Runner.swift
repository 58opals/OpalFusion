import Foundation

struct Options {
    let repoRoot: URL
    var mode: String
    let focus: String?
    let log: String?

    init(arguments: [String]) throws {
        var repo: String?
        var mode = "develop"
        var focus: String?
        var log: String?
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            guard ["--repo-root", "--mode", "--focus", "--log"].contains(flag), index + 1 < arguments.count else {
                throw ValidationFailure("Expected --repo-root PATH [--mode MODE] [--focus FILTER] [--log PATH]")
            }
            index += 1
            switch flag {
            case "--repo-root": repo = arguments[index]
            case "--mode": mode = arguments[index]
            case "--focus": focus = arguments[index]
            default: log = arguments[index]
            }
            index += 1
        }
        guard let repo, !repo.isEmpty else { throw ValidationFailure("--repo-root is required") }
        guard cashFusionModes.union(mosaicModes).union(["all", "assurance", "profile-log"]).contains(mode) else { throw ValidationFailure("Unknown validation mode: \(mode)") }
        let focused = ["cashfusion-focused", "mosaic-focused"].contains(mode)
        if focus != nil && !focused { throw ValidationFailure("A test filter is accepted only by a focused mode") }
        if focused {
            guard let focus, !focus.isEmpty else { throw ValidationFailure("\(mode) requires one nonempty test filter") }
            _ = try regularExpression(focus)
        }
        if mode == "profile-log" {
            guard let log, !log.isEmpty else { throw ValidationFailure("profile-log requires one log path") }
        } else if log != nil { throw ValidationFailure("A log path is accepted only by profile-log") }
        self.repoRoot = URL(fileURLWithPath: repo).standardizedFileURL.resolvingSymlinksInPath()
        self.mode = mode
        self.focus = focus
        self.log = log
    }
    init(repoRoot: URL, mode: String, focus: String? = nil) {
        self.repoRoot = repoRoot
        self.mode = mode
        self.focus = focus
        self.log = nil
    }
}

func swiftPMFlags(repoRoot: URL, engine: String, environment: [String: String]) throws -> (flags: [String], moduleCache: String) {
    let lane = repoRoot.appendingPathComponent(".build/validation/\(engine)")
    func path(_ variable: String, _ fallback: URL) -> String {
        let value = environment[variable] ?? fallback.path
        let target = value.hasPrefix("/") ? URL(fileURLWithPath: value) : repoRoot.appendingPathComponent(value)
        return target.standardizedFileURL.resolvingSymlinksInPath().path
    }
    let scratch = path("OPALFUSION_SPM_SCRATCH_PATH", lane.appendingPathComponent("build"))
    let module = path("OPALFUSION_SPM_MODULE_CACHE_PATH", lane.appendingPathComponent("module-cache"))
    try FileManager.default.createDirectory(atPath: module, withIntermediateDirectories: true)
    return (["--package-path", repoRoot.appendingPathComponent(engine == "cashfusion" ? "Tests/CashFusion" : "Tests/Mosaic").path,
             "--scratch-path", scratch, "--cache-path", path("OPALFUSION_SPM_CACHE_PATH", URL(fileURLWithPath: scratch)),
             "--config-path", path("OPALFUSION_SPM_CONFIG_PATH", lane.appendingPathComponent("config")),
             "--security-path", path("OPALFUSION_SPM_SECURITY_PATH", lane.appendingPathComponent("security")),
             "--manifest-cache", "local"], module)
}

func builtSwiftTestingCommand(process: ValidationExecuting, flags: [String], module: String, deadline: Double) throws -> [String] {
    let outputs = try [
        process.run(["swift", "build"] + flags + ["--show-bin-path"], deadline: deadline, capture: true),
        process.run(["xcrun", "--find", "swift"], deadline: deadline, capture: true),
        process.run(["xcrun", "--sdk", "macosx", "--show-sdk-platform-path"], deadline: deadline, capture: true)
    ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard outputs.allSatisfy({ $0.hasPrefix("/") }) else { throw ValidationFailure("SwiftPM products and selected Xcode paths must be absolute") }
    let products = URL(fileURLWithPath: outputs[0])
    let compiler = URL(fileURLWithPath: outputs[1])
    let platform = URL(fileURLWithPath: outputs[2])
    let helper = compiler.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("libexec/swift/pm/swiftpm-testing-helper")
    let bundle = products.appendingPathComponent("\(module).xctest/Contents/MacOS/\(module)")
    guard FileManager.default.isExecutableFile(atPath: helper.path), FileManager.default.fileExists(atPath: bundle.path) else {
        throw ValidationFailure("The selected Swift Testing helper or built test bundle is missing")
    }
    for (key, path) in [("DYLD_FRAMEWORK_PATH", platform.appendingPathComponent("Developer/Library/Frameworks")),
                        ("DYLD_LIBRARY_PATH", platform.appendingPathComponent("Developer/usr/lib"))] {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path.path, isDirectory: &directory), directory.boolValue else {
            throw ValidationFailure("The selected Xcode test-library directory is missing")
        }
        let prior = process.environment[key].flatMap { $0.isEmpty ? nil : $0 }
        process.environment[key] = path.path + (prior.map { ":" + $0 } ?? "")
    }
    return [helper.path, "--test-bundle-path", bundle.path, "--testing-library", "swift-testing"]
}

func validateFocusedExecution(at report: URL) throws {
    // SwiftPM gives Swift Testing its own output suffix when the package may
    // also contain XCTest. Require its actual result, not discovery alone:
    // SwiftPM can return zero when a discovery-matching regex executes nothing.
    let suffixed = report.deletingLastPathComponent()
        .appendingPathComponent(report.deletingPathExtension().lastPathComponent + "-swift-testing.xml")
    let path = FileManager.default.fileExists(atPath: suffixed.path) ? suffixed : report
    guard FileManager.default.fileExists(atPath: path.path) else {
        throw ValidationFailure("Focused execution produced no test result; discovery alone is not passing coverage")
    }
    let document = try XMLDocument(contentsOf: path, options: [.nodeLoadExternalEntitiesNever])
    guard let root = document.rootElement(), ["testsuites", "testsuite"].contains(root.name ?? ""),
          !(try document.nodes(forXPath: "//testcase[not(skipped)]")).isEmpty,
          (try document.nodes(forXPath: "//failure | //error")).isEmpty else {
        throw ValidationFailure("Focused execution has no executed cases or contains failures")
    }
}

func runLane(_ options: Options, environment: [String: String],
             process supplied: ValidationExecuting? = nil,
             buildBudget: Double = buildBudgetSeconds, postBudget: Double = postBuildBudgetSeconds,
             clock: () -> Double = monotonicTime,
             emit: (String, Bool) -> Void) -> Int32 {
    var stage = "build"
    var result = "FAIL"
    var postStarted: Double?
    var budget: Double?
    defer {
        let elapsed = postStarted.map { String(format: "%.3fs", clock() - $0) } ?? "not started"
        emit("Post-build elapsed: \(elapsed); budget: \(budget.map { String(Int($0)) } ?? "not applicable")s; result: \(result)", false)
    }
    do {
        let plan = try selectionPlan(options.mode, focus: options.focus)
        budget = cashFusionModes.contains(options.mode) && plan.budget != nil ? postBudget : plan.budget
        let engine = plan.module == "CashFusionEngineTests" ? "cashfusion" : "mosaic"
        let (flags, moduleCache) = try swiftPMFlags(repoRoot: options.repoRoot, engine: engine, environment: environment)
        var childEnvironment = environment
        childEnvironment["OPALFUSION_EC_INTEROP"] = ""
        childEnvironment["CLANG_MODULE_CACHE_PATH"] = moduleCache
        let process = supplied ?? ValidationProcess(environment: childEnvironment)
        process.environment = childEnvironment
        let buildStarted = clock()
        emit("\(options.mode) local validation: build budget \(Int(buildBudget))s; post-build budget \(budget.map { String(Int($0)) } ?? "not applicable")s; live coordinator proof disabled.", false)
        if engine == "mosaic" && options.mode != "mosaic-fast" {
            emit("Explicit deferred Mosaic lane; historical combined Debug runtime: approximately 97 minutes.", false)
        }
        var direct: [String]?
        do {
            defer { emit(String(format: "Build elapsed: %.3fs", clock() - buildStarted), false) }
            _ = try process.run(["swift", "build"] + flags + ["--build-tests"], deadline: buildStarted + buildBudget, capture: false)
            if options.mode == "mosaic-fast" {
                direct = try builtSwiftTestingCommand(process: process, flags: flags, module: plan.module, deadline: buildStarted + buildBudget)
            }
        }
        if options.mode == "build" { result = "PASS (CashFusion harness build only)"; return 0 }
        let started = clock()
        postStarted = started
        let deadline = started + (budget ?? 0)
        stage = "discovery"
        let listingCommand = direct.map { $0 + ["--list-tests"] } ?? (["swift", "test"] + flags + ["list", "--skip-build"])
        let listing = try process.run(listingCommand, deadline: deadline, capture: true)
        let discovered = try validateDiscovery(listing, module: plan.module, suites: plan.suites, selection: plan.selection) { emit($0, false) }
        try validatePartitions(identifiers: discovered.identifiers, selected: discovered.selected, phases: plan.phases)
        for phase in plan.phases {
            guard try discovered.selected.contains(where: { try phase.owns($0) }) else { continue }
            stage = phase.name
            emit("Running \(stage) (build skipped).", false)
            var command = direct.map { $0 + phase.arguments } ?? (["swift", "test"] + flags + ["--skip-build"] + phase.arguments)
            var executionReport: URL?
            if ["cashfusion-focused", "mosaic-focused"].contains(options.mode) {
                let directory = options.repoRoot.appendingPathComponent(".build/validation/\(engine)/focused-results")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let path = directory.appendingPathComponent(UUID().uuidString + ".xml")
                executionReport = path
                command += ["--xunit-output", path.path]
            }
            let phaseStarted = clock()
            do {
                defer { emit(String(format: "Phase elapsed: %.3fs; %@", clock() - phaseStarted, stage), false) }
                _ = try process.run(command, deadline: deadline, capture: false)
                if let executionReport { try validateFocusedExecution(at: executionReport) }
            }
        }
        result = ["fast", "cashfusion-all", "mosaic", "mosaic-all"].contains(options.mode) ? "PASS (complete harness)" : "PASS (selected scope only)"
        return 0
    } catch let error as ValidationTimeout {
        emit("FAIL during \(stage): \(error); no retry or budget extension.", true)
        return 124
    } catch let error as ValidationInterrupted {
        emit("FAIL during \(stage): \(error).", true)
        return 128 + error.signal
    } catch let error as CommandFailure {
        emit("FAIL during \(stage): \(error)", true)
        return max(1, min(125, error.status))
    } catch {
        emit("FAIL during \(stage): \(error)", true)
        return 1
    }
}

public enum ValidationCommand {
    public static func run(arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment,
                           emit: (String, Bool) -> Void = writeLine) -> Int32 {
        do {
            var options = try Options(arguments: arguments)
            if options.mode == "profile-log" {
                try reportTimings(at: URL(fileURLWithPath: options.log!), emit: { emit($0, false) })
                return 0
            }
            try validateSourceGuards(repoRoot: options.repoRoot, mode: options.mode)
            let signals = SignalScope()
            defer { withExtendedLifetime(signals) {} }
            let modes = ["all", "assurance"].contains(options.mode) ? ["cashfusion-all", "mosaic-all"] : [options.mode]
            for mode in modes {
                options.mode = mode
                let result = runLane(options, environment: environment, emit: emit)
                if result != 0 { return result }
            }
            return 0
        } catch {
            emit("Invalid validation selection: \(error)", true)
            return 1
        }
    }
}

public func writeLine(_ line: String, _ error: Bool) {
    let handle = error ? FileHandle.standardError : .standardOutput
    handle.write(Data((line + "\n").utf8))
}
