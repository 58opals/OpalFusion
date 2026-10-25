import Darwin
import Foundation
import Testing
@testable import FusionValidation

@Suite(.serialized)
struct ValidationLoopContract {
    @Test func defaultDevelopmentIsFocusedAndCompleteAliasesKeepTheirDispatch() throws {
        let fixture = try RunnerFixture()
        let first = try fixture.invoke()
        let second = try fixture.invoke("fast")
        let third = try fixture.invoke("cashfusion-all")
        #expect(try Options(arguments: ["--repo-root", fixture.root.path]).mode == "develop")
        for result in [first, second, third] {
            #expect(result.code == 0)
            #expect(result.output.contains("budget: 60s"))
        }
        #expect(first.output.contains("PASS (selected scope only)"))
        #expect(second.output.contains("PASS (complete harness)"))
        #expect(third.output.contains("PASS (complete harness)"))
        #expect(NSDictionary(dictionary: ["calls": second.calls]).isEqual(to: ["calls": third.calls]))
        #expect(phaseNames(first.calls) == ["build", "discovery", "client", "bounded"])
        #expect(arguments(first.calls[0]).contains("--build-tests"))
        for call in first.calls {
            #expect(call["interop"] as? String == "")
            let args = arguments(call)
            let index = try #require(args.firstIndex(of: "--package-path"))
            #expect(args[index + 1] == fixture.root.appendingPathComponent("Tests/CashFusion").path)
        }
        for call in first.calls.dropFirst() { #expect(arguments(call).contains("--skip-build")) }
        #expect(arguments(first.calls.last!).last == (try suiteFilter(boundedSuites)))
        #expect(!arguments(second.calls.last!).contains("--filter"))
        #expect(arguments(second.calls.last!).last == (try suiteFilter([clientSuite])))
        let plan = try selectionPlan("develop")
        let discovery = try validateDiscovery(fixture.listing[plan.module]!.joined(separator: "\n"), module: plan.module, suites: plan.suites, selection: plan.selection) { _ in }
        #expect(discovery.selected.count < discovery.identifiers.count)
        #expect(!discovery.selected.contains { $0.contains("CashFusionAdditionalValidator") })
        try validatePartitions(identifiers: discovery.identifiers, selected: discovery.selected, phases: plan.phases)
    }

    @Test func cashFusionDoesNotReadOrBuildMosaic() throws {
        let fixture = try RunnerFixture()
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("Tests/Mosaic"))
        let result = try fixture.invoke()
        #expect(result.code == 0)
        #expect(!result.calls.isEmpty)
        #expect(!String(data: try JSONSerialization.data(withJSONObject: result.calls), encoding: .utf8)!.contains("Mosaic"))
    }

    @Test func invalidArgumentsDoNotInvokeSwift() throws {
        let fixture = try RunnerFixture()
        for args in [["--mode", "unknown"], ["--mode", "fast", "extra"], ["--mode", "cashfusion-focused"],
                     ["--mode", "cashfusion-focused", "--focus", ""], ["--mode", "cashfusion-focused", "--focus", "["],
                     ["--mode", "mosaic-focused"], ["--mode", "mosaic-focused", "--focus", "["],
                     ["--mode", "profile-log"], ["--mode", "develop", "--log", "file"]] {
            try write("", to: fixture.calls)
            let code = ValidationCommand.run(arguments: ["--repo-root", fixture.root.path] + args, environment: fixture.environment) { _, _ in }
            #expect(code != 0)
            #expect(try fixture.readCalls().isEmpty)
        }
        // The stable shell boundary also rejects extra positional arguments.
        let process = ValidationProcess(environment: fixture.environment)
        #expect(throws: CommandFailure.self) {
            try process.run(["/bin/zsh", repositoryRoot().appendingPathComponent("scripts/run-validation-loop.sh").path, "fast", "extra"], deadline: monotonicTime() + 5, capture: true)
        }
        #expect(try fixture.readCalls().isEmpty)
    }

    @Test func missingEmptyDuplicateAndForeignDiscoveryFailBeforeTests() throws {
        let fixture = try RunnerFixture()
        let complete = fixture.listing["CashFusionEngineTests"]!
        for listing in [[], Array(complete.dropFirst()), complete + [complete[0]], complete + ["MosaicEngineTests.Foreign/validate()"]] {
            var all = fixture.listing
            all["CashFusionEngineTests"] = listing
            try JSONSerialization.data(withJSONObject: all).write(to: fixture.discovery)
            let result = try fixture.invoke()
            #expect(result.code != 0)
            #expect(phaseNames(result.calls) == ["build", "discovery"])
        }
    }

    @Test func failureStopsRemainingCommandsWithoutRetry() throws {
        let fixture = try RunnerFixture()
        for (phase, code, count) in [("build", 17, 1), ("discovery", 18, 2), ("client", 19, 3), ("bounded", 20, 4)] {
            let result = try fixture.invoke(scenario: "fail-" + phase)
            #expect(result.code == Int32(code))
            #expect(result.calls.count == count)
            #expect(!result.output.contains("result: PASS"))
            #expect(result.output.contains("Build elapsed:"))
            #expect(result.output.contains("Post-build elapsed:"))
        }
        let signaled = try fixture.invoke(scenario: "signal-build")
        #expect(signaled.code == 1)
        #expect(signaled.calls.count == 1)
        #expect(!signaled.output.contains("result: PASS"))
    }

    @Test func mosaicGuardsRunBeforeBuildAndCoverExplicitEngineImports() throws {
        let fixture = try RunnerFixture()
        for (name, content, mode) in [
            (mosaicFastSuites[0], "ExecutionFixture.prepare()", "mosaic-fast"),
            ("MosaicMainnetAlphaReservationCoordinatorDependencyValidator", "LocalContributionMaterial.build()", "mosaic-all"),
            ("MosaicPrivateAlphaRuntimeRecoveryValidator", "@_spi(MosaicPrivateAlpha) @testable import MosaicEngine", "mosaic-private-alpha-consumer-surface"),
            ("RFC9500RSATestKeyFixture", "RSABSSA.SigningKey\n  .generate()", "mosaic-private-alpha-transport")
        ] {
            let path = fixture.sources.appendingPathComponent(name + ".swift")
            try write(content, to: path)
            let result = try fixture.invoke(mode)
            #expect(result.code != 0)
            #expect(result.calls.isEmpty)
            try write("// Guard fixture\n", to: path)
        }
    }

    @Test func emptyOrDuplicateSuiteSelectorsAreRejected() throws {
        for names in [[], [""], ["A", "A"], ["A|B"]] {
            #expect(throws: ValidationFailure.self) { try suiteFilter(names) }
        }
    }

    @Test func missingOrUnreadableGuardInputFailsBeforeBuild() throws {
        let fixture = try RunnerFixture()
        let path = fixture.sources.appendingPathComponent(mosaicFastSuites[0] + ".swift")
        try FileManager.default.removeItem(at: path)
        var result = try fixture.invoke("mosaic-fast")
        #expect(result.code != 0)
        #expect(result.calls.isEmpty)
        try Data([255]).write(to: path)
        result = try fixture.invoke("mosaic-fast")
        #expect(result.code != 0)
        #expect(result.calls.isEmpty)
    }

    @Test func mosaicFastReusesExactBuiltBundleWithMatchingRuntime() throws {
        let fixture = try RunnerFixture()
        let result = try fixture.invoke("mosaic-fast")
        #expect(result.code == 0)
        #expect(phaseNames(result.calls) == ["build", "products", "toolchain", "platform", "discovery", "bounded"])
        let bundle = fixture.root.appendingPathComponent("products/MosaicEngineTests.xctest/Contents/MacOS/MosaicEngineTests")
        for call in result.calls.suffix(2) {
            let args = arguments(call)
            #expect(args[try #require(args.firstIndex(of: "--test-bundle-path")) + 1] == bundle.path)
        }
        final class MetadataProcess: ValidationExecuting {
            var environment = ["DYLD_FRAMEWORK_PATH": "/existing/frameworks"]
            var outputs: [String]
            var lastDeadline: Double?
            init(root: URL) { outputs = ["products", "toolchain/usr/bin/swift", "Platform"].map { root.appendingPathComponent($0).path } }
            func run(_ command: [String], deadline: Double?, capture: Bool) -> String {
                lastDeadline = deadline
                return outputs.removeFirst()
            }
        }
        let metadata = MetadataProcess(root: fixture.root)
        _ = try builtSwiftTestingCommand(process: metadata, flags: [], module: "MosaicEngineTests", deadline: 300)
        #expect(metadata.lastDeadline == 300)
        #expect(metadata.environment["DYLD_FRAMEWORK_PATH"] == fixture.root.appendingPathComponent("Platform/Developer/Library/Frameworks").path + ":/existing/frameworks")
        #expect(metadata.environment["DYLD_LIBRARY_PATH"] == fixture.root.appendingPathComponent("Platform/Developer/usr/lib").path)
        #expect(arguments(result.calls.last!).contains("--experimental-maximum-parallelization-width"))
        #expect(result.output.contains("budget: 15s"))
        try FileManager.default.removeItem(at: bundle)
        let missing = try fixture.invoke("mosaic-fast")
        #expect(missing.code != 0)
        #expect(!phaseNames(missing.calls).contains(where: { ["discovery", "bounded"].contains($0) }))
    }

    @Test func buildTimeoutPrecedesDiscoveryAndHasOwnDeadline() throws {
        let fixture = try RunnerFixture()
        let result = try fixture.direct(scenario: "slow-build", buildBudget: 0.2, postBudget: 0.1)
        #expect(result.code == 124)
        #expect(phaseNames(result.calls) == ["build"])
        #expect(result.output.contains("FAIL during build"))
        #expect(result.output.contains("Post-build elapsed: not started"))
    }

    @Test func buildTimeDoesNotConsumePostBuildDeadline() throws {
        let fixture = try RunnerFixture()
        let result = try fixture.direct(scenario: "slow-build", buildBudget: 2, postBudget: 0.8)
        #expect(result.code == 0)
        #expect(phaseNames(result.calls) == ["build", "discovery", "client", "bounded"])
    }

    @Test func discoveryIsInsideAggregateDeadline() throws {
        let fixture = try RunnerFixture()
        let result = try fixture.direct(scenario: "slow-discovery", postBudget: 0.2)
        #expect(result.code == 124)
        #expect(result.output.contains("FAIL during discovery"))
        #expect(phaseNames(result.calls) == ["build", "discovery"])
    }

    @Test func budgetIsSharedAcrossDiscoveryAndBothTestProcesses() throws {
        let fixture = try RunnerFixture()
        final class ClockProcess: ValidationExecuting {
            var environment: [String: String] = [:]
            var now = 0.0
            var commands: [[String]] = []
            var deadlines: [Double?] = []
            let listing: String
            init(listing: String) { self.listing = listing }
            func run(_ command: [String], deadline: Double?, capture: Bool) throws -> String {
                commands.append(command)
                deadlines.append(deadline)
                now += command[1] == "build" ? 100 : 0.3
                if let deadline, now > deadline { throw ValidationTimeout() }
                return capture ? listing : ""
            }
        }
        let process = ClockProcess(listing: fixture.listing["CashFusionEngineTests"]!.joined(separator: "\n"))
        var output = ""
        let code = runLane(Options(repoRoot: fixture.root, mode: "fast"), environment: fixture.environment, process: process, postBudget: 0.8, clock: { process.now }) { line, _ in output += line + "\n" }
        #expect(code == 124)
        #expect(process.commands.count == 4)
        #expect(process.deadlines[0] == 300)
        #expect(Array(process.deadlines.dropFirst()) == [100.8, 100.8, 100.8])
        #expect(output.contains("remaining CashFusion tests"))
    }

    @Test func overriddenPathsAreRootRelativeBeforeNestedPackageDispatch() throws {
        let fixture = try RunnerFixture()
        let overrides = ["OPALFUSION_SPM_SCRATCH_PATH": "warm/build", "OPALFUSION_SPM_CACHE_PATH": "warm/cache", "OPALFUSION_SPM_CONFIG_PATH": "warm/config", "OPALFUSION_SPM_SECURITY_PATH": "warm/security", "OPALFUSION_SPM_MODULE_CACHE_PATH": "warm/module"]
        let result = try fixture.invoke(overrides: overrides)
        #expect(result.code == 0)
        for call in result.calls {
            let args = arguments(call)
            for (flag, name) in [("--scratch-path", "build"), ("--cache-path", "cache"), ("--config-path", "config"), ("--security-path", "security")] {
                #expect(args[try #require(args.firstIndex(of: flag)) + 1] == fixture.root.appendingPathComponent("warm/" + name).path)
            }
            #expect(call["module_cache"] as? String == fixture.root.appendingPathComponent("warm/module").path)
        }
    }

    @Test func namedModesSelectPackageAndKeepSkipBuildAndLiveExclusion() throws {
        let fixture = try RunnerFixture()
        let modes: [(String, String, Int)] = [("build", "CashFusion", 1), ("codec", "CashFusion", 3), ("round", "CashFusion", 3), ("runtime", "CashFusion", 3), ("workflow", "CashFusion", 3), ("client", "CashFusion", 3), ("interop-parser", "CashFusion", 3), ("mosaic", "Mosaic", 5), ("mosaic-all", "Mosaic", 5), ("mosaic-fast", "Mosaic", 6), ("mosaic-private-alpha-consumer-surface", "Mosaic", 3), ("mosaic-private-alpha-spi", "Mosaic", 4), ("mosaic-private-alpha-transport", "Mosaic", 3), ("mosaic-rehearsal", "Mosaic", 3)]
        for (mode, package, count) in modes {
            let result = try fixture.invoke(mode)
            #expect(result.code == 0, "\(mode): \(result.output)")
            #expect(result.calls.count == count)
            for call in result.calls {
                let args = arguments(call)
                if let index = args.firstIndex(of: "--package-path") { #expect(URL(fileURLWithPath: args[index + 1]).lastPathComponent == package) }
                else if ["discovery", "bounded"].contains(call["phase"] as? String ?? "") {
                    #expect(args.contains("--test-bundle-path"))
                    #expect(args[try #require(args.firstIndex(of: "--testing-library")) + 1] == "swift-testing")
                }
                #expect(call["interop"] as? String == "")
                if args.first == "test" { #expect(args.contains("--skip-build")) }
            }
            if mode == "mosaic-fast" { #expect(result.output.contains("budget: 15s")) }
            else if package == "Mosaic" { #expect(result.output.contains("budget: 7200s")) }
        }
    }

    @Test func combinedAllKeepsCompleteDisjointEnginePartitions() throws {
        let fixture = try RunnerFixture()
        let result = try fixture.invoke("all")
        #expect(result.code == 0)
        let assurance = try fixture.invoke("assurance")
        #expect(assurance.code == 0)
        #expect(NSDictionary(dictionary: ["calls": result.calls]).isEqual(to: ["calls": assurance.calls]))
        #expect(result.calls.count == 9)
        #expect(try result.calls.map { call -> String in
            let args = arguments(call)
            return URL(fileURLWithPath: args[try #require(args.firstIndex(of: "--package-path")) + 1]).lastPathComponent
        } == [String](repeating: "CashFusion", count: 4) + [String](repeating: "Mosaic", count: 5))
        #expect(result.output.contains("budget: 60s"))
        #expect(result.output.contains("budget: 7200s"))
        for mode in ["cashfusion-all", "mosaic-all"] {
            let plan = try selectionPlan(mode)
            let discovery = try validateDiscovery(fixture.listing[plan.module]!.joined(separator: "\n"), module: plan.module, suites: plan.suites, selection: plan.selection) { _ in }
            #expect(discovery.identifiers == discovery.selected)
            try validatePartitions(identifiers: discovery.identifiers, selected: discovery.selected, phases: plan.phases)
        }
    }

    @Test func focusedFilterRequiresMatchesAndPreservesSerialExecution() throws {
        let fixture = try RunnerFixture()
        for (mode, filter, budget) in [("cashfusion-focused", "RoundEngineScriptedValidator", "60s"),
                                       ("mosaic-focused", "MosaicPrivateAlphaRuntimeSPIValidator", "7200s")] {
            let result = try fixture.invoke(mode, focus: filter)
            #expect(result.code == 0)
            #expect(result.calls.count == 3)
            #expect(arguments(result.calls.last!).contains("--no-parallel"))
            #expect(result.output.contains("budget: " + budget))
            #expect(result.output.contains("PASS (selected scope only)"))
            let missing = try fixture.invoke(mode, focus: "DoesNotExist")
            #expect(missing.code != 0)
            #expect(missing.calls.count == 2)
            for scenario in ["empty-execution", "missing-execution-proof"] {
                let empty = try fixture.invoke(mode, focus: filter, scenario: scenario)
                #expect(empty.code != 0)
                #expect(empty.calls.count == 3)
                #expect(!empty.output.contains("result: PASS"))
            }
        }
    }

    @Test func focusedExecutionRequiresRealUnskippedSuccessfulResult() throws {
        let fixture = try RunnerFixture()
        let report = fixture.root.appendingPathComponent("result.xml")
        for contents in ["<testsuites/>", "<testsuites><testsuite><testcase><skipped/></testcase></testsuite></testsuites>",
                         "<testsuites><testsuite><testcase><failure/></testcase></testsuite></testsuites>", "not XML"] {
            try write(contents, to: report)
            #expect(throws: (any Error).self) { try validateFocusedExecution(at: report) }
        }
        try FileManager.default.removeItem(at: report)
        let suffixed = fixture.root.appendingPathComponent("result-swift-testing.xml")
        try write("<testsuites><testsuite><testcase name=\"actual\"/></testsuite></testsuites>", to: suffixed)
        try validateFocusedExecution(at: report)
    }
}
