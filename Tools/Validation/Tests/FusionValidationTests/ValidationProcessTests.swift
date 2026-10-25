import Darwin
import Foundation
import Testing
@testable import FusionValidation

@Suite(.serialized)
struct ValidationProcessContract {
    @Test func uncapturedChildInheritsStandardInputOutputAndError() throws {
        let result = try invokeStandardStreams(mode: "build", scenario: "standard-streams-build")
        #expect(result.code == 0)
        #expect(result.stdout.contains("inherited stdout from build\n"))
        #expect(result.stderr == "inherited stderr from build\n")
    }

    @Test func capturedChildInheritsStandardInputAndErrorWhileCapturingOutput() throws {
        let result = try invokeStandardStreams(mode: "fast", scenario: "standard-streams-discovery")
        #expect(result.code == 0)
        #expect(result.stderr == "inherited stderr from discovery\n")
        // Successful suite discovery proves the child's exact stdout reached
        // ValidationProcess; it must not leak to the inherited destination.
        #expect(!result.stdout.contains("CashFusionEngineTests.\(clientSuite)/validate()"))
        #expect(result.stdout.contains("PASS (complete harness)"))
    }

    private func invokeStandardStreams(mode: String, scenario: String) throws -> (code: Int32, stdout: String, stderr: String) {
        let fixture = try RunnerFixture()
        let input = fixture.root.appendingPathComponent("stdin.txt")
        let output = fixture.root.appendingPathComponent("stdout.txt")
        let error = fixture.root.appendingPathComponent("stderr.txt")
        try write("inherited standard input\n", to: input)
        try write("", to: output)
        try write("", to: error)
        let stdin = try FileHandle(forReadingFrom: input)
        let stdout = try FileHandle(forWritingTo: output)
        let stderr = try FileHandle(forWritingTo: error)
        defer { try? stdin.close(); try? stdout.close(); try? stderr.close() }
        let process = Process()
        process.executableURL = fixture.commandExecutable
        process.arguments = ["--repo-root", fixture.root.path, "--mode", mode]
        process.environment = fixture.environment.merging(["RUNNER_SCENARIO": scenario], uniquingKeysWith: { _, new in new })
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        defer { if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() } }
        let code = try waitForExit(process)
        return (code, try String(contentsOf: output, encoding: .utf8), try String(contentsOf: error, encoding: .utf8))
    }

    @Test func unrelatedParentDescriptorsAreClosedBeforeExecution() throws {
        let fixture = try RunnerFixture()
        let file = fixture.root.appendingPathComponent("parent-only.txt")
        try write("parent-only descriptor\n", to: file)
        let original = open(file.path, O_RDONLY)
        #expect(original >= 0)
        defer { close(original) }
        let descriptor = fcntl(original, F_DUPFD, 200)
        #expect(descriptor >= 200)
        defer { close(descriptor) }
        #expect(fcntl(descriptor, F_GETFD) & FD_CLOEXEC == 0)
        let process = ValidationProcess(environment: fixture.environment)
        _ = try process.run([fixture.fixtureExecutable.path, "closed-descriptor", String(descriptor)], deadline: monotonicTime() + 5)
        #expect(fcntl(descriptor, F_GETFD) >= 0)
    }

    @Test func capturedDescendantOutputRetainsDeadlineAfterRootExit() throws {
        let fixture = try RunnerFixture()
        let marker = fixture.root.appendingPathComponent("inherited-output.pid")
        let process = ValidationProcess(environment: fixture.environment)
        defer {
            if let text = try? String(contentsOf: marker, encoding: .utf8), let pid = Int32(text), kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
        #expect(throws: ValidationTimeout.self) {
            try process.run([fixture.fixtureExecutable.path, "owned-process", marker.path, "--descendant", "--exit-parent"], deadline: monotonicTime() + 0.3, capture: true)
        }
        try waitFor(marker)
        let descendant = try #require(Int32(String(contentsOf: marker, encoding: .utf8)))
        #expect(stopped(descendant))
    }

    @Test func interruptDuringLaunchStillCleansNewProcess() throws {
        let fixture = try RunnerFixture()
        let marker = fixture.root.appendingPathComponent("launch.pid")
        // The child signals its native owner immediately after spawn. This
        // exercises the real launch boundary rather than mocking spawn state.
        let parent = try fixture.launchCommand(scenario: "signal-parent", marker: marker)
        defer { if parent.isRunning { kill(parent.processIdentifier, SIGKILL); parent.waitUntilExit() } }
        #expect(try waitForExit(parent) == 128 + SIGTERM)
        try waitFor(marker)
        let pid = try #require(Int32(String(contentsOf: marker, encoding: .utf8)))
        #expect(stopped(pid))
    }

    @Test func timeoutProbePermissionFailureStillKillsDescendantsAndPreservesUnrelatedProcess() throws {
        let fixture = try RunnerFixture()
        let marker = fixture.root.appendingPathComponent("child.pid")
        let unrelatedMarker = fixture.root.appendingPathComponent("unrelated.pid")
        let unrelated = Process()
        unrelated.executableURL = fixture.fixtureExecutable
        unrelated.arguments = ["owned-process", unrelatedMarker.path, "--ignore-term"]
        try unrelated.run()
        defer { if unrelated.isRunning { kill(unrelated.processIdentifier, SIGKILL); unrelated.waitUntilExit() } }
        try waitFor(unrelatedMarker)
        var probes: [pid_t] = []
        var delivered: [(pid_t, Int32)] = []
        let process = ValidationProcess(environment: fixture.environment) { pid, number in
            if number == 0 { probes.append(pid); errno = EPERM; return -1 }
            delivered.append((pid, number))
            return kill(-pid, number)
        }
        let start = monotonicTime()
        #expect(throws: ValidationTimeout.self) {
            try process.run([fixture.fixtureExecutable.path, "owned-process", marker.path, "--descendant"], deadline: start + 0.4)
        }
        #expect(monotonicTime() - start < 5.9)
        #expect(!probes.isEmpty)
        #expect(delivered.map(\.1) == [SIGTERM, SIGKILL])
        #expect(Set(delivered.map(\.0)).count == 1)
        #expect(unrelated.isRunning)
        try waitFor(marker)
        let descendant = try #require(Int32(String(contentsOf: marker, encoding: .utf8)))
        defer { if kill(descendant, 0) == 0 { kill(descendant, SIGKILL) } }
        #expect(stopped(descendant))
    }

    @Test func realSignalPermissionFailureIsNotAcceptedAsCleanup() throws {
        let fixture = try RunnerFixture()
        let marker = fixture.root.appendingPathComponent("denied.pid")
        let process = ValidationProcess(environment: fixture.environment) { _, _ in errno = EPERM; return -1 }
        defer {
            if let pid = process.active {
                kill(-pid, SIGKILL)
                var status: Int32 = 0
                _ = waitpid(pid, &status, 0)
            }
        }
        do {
            _ = try process.run([fixture.fixtureExecutable.path, "owned-process", marker.path], deadline: monotonicTime() + 0.2)
            Issue.record("Denied real signal delivery was accepted as successful cleanup")
        } catch let error as ProcessFailure {
            #expect(error.code == EPERM)
            #expect(error.operation == "killpg(SIGTERM)")
        }
        #expect(process.active != nil)
        if let pid = process.active { #expect(kill(pid, 0) == 0) }
    }

    @Test func interruptCleansOwnedGroup() throws {
        for number in [SIGINT, SIGTERM] {
            let fixture = try RunnerFixture()
            let marker = fixture.root.appendingPathComponent("owned.pid")
            let parent = try fixture.launchCommand(scenario: "owned-build", marker: marker)
            defer { if parent.isRunning { kill(parent.processIdentifier, SIGKILL); parent.waitUntilExit() } }
            try waitFor(marker)
            kill(parent.processIdentifier, number)
            #expect(try waitForExit(parent) == 128 + number)
            let owned = try #require(Int32(String(contentsOf: marker, encoding: .utf8)))
            #expect(stopped(owned))
        }
    }
}
