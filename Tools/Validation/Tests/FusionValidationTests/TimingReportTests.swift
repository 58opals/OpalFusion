import Foundation
import Testing
@testable import FusionValidation

struct TimingReportContract {
    @Test func historicalLogRanksOverlappingWallTimesWithoutRunningTests() throws {
        let fixture = try RunnerFixture()
        let log = fixture.root.appendingPathComponent("timings.log")
        try write("""
        ✔ Test "short" passed after 1.500 seconds.
        ✔ Test "long" with 3 test cases passed after 9.250 seconds.
        ✔ Suite "overlapping" passed after 10.000 seconds.
        ✔ Test run with 4 tests in 1 suite passed after 10.200 seconds.
        ✔ Test "failed proof" failed after 3.000 seconds.
        ◇ Test "unfinished" started.
        """, to: log)
        var output: [String] = []
        let code = ValidationCommand.run(arguments: ["--repo-root", fixture.root.path, "--mode", "profile-log", "--log", log.path], environment: fixture.environment) { line, _ in output.append(line) }
        #expect(code == 0)
        #expect(try fixture.readCalls().isEmpty)
        #expect(output.contains { $0.contains("no current validation acceptance") })
        #expect(output.contains { $0.contains("Harness: 10.200s") })
        #expect(output.firstIndex(where: { $0.contains("9.250s") })! < output.firstIndex(where: { $0.contains("1.500s") })!)
        #expect(output.contains { $0.contains("3.000s; failed") })
        #expect(!output.contains { $0.contains("unfinished") })
        #expect(output.contains { $0.contains("overlapping records must not be summed") })
        #expect(!output.contains { $0.contains("result: PASS") })
    }

    @Test func emptyUnreadableAndOversizedTimingInputsFail() throws {
        let fixture = try RunnerFixture()
        let path = fixture.root.appendingPathComponent("timings.log")
        for data in [Data(), Data("Test started; no completed record".utf8), Data([255])] {
            try data.write(to: path)
            #expect(throws: (any Error).self) { try reportTimings(at: path) { _ in } }
        }
        let handle = try FileHandle(forWritingTo: path)
        try handle.truncate(atOffset: 64 * 1_024 * 1_024 + 1)
        try handle.close()
        #expect(throws: (any Error).self) { try reportTimings(at: path) { _ in } }
        #expect(throws: (any Error).self) { try reportTimings(at: fixture.root) { _ in } }
    }
}
