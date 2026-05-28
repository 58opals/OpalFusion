// InstantValidator.swift

@testable import OpalFusion
import Testing

struct InstantValidator {
    @Test("Execution instant clamps distance across representable bounds without trapping")
    func validateDistanceClampsAcrossBounds() {
        let earliest = OpalFusion.Execution.Instant(millisecondsSinceUnixEpoch: Int64.min)
        let latest = OpalFusion.Execution.Instant(millisecondsSinceUnixEpoch: Int64.max)

        #expect(earliest.distance(to: latest).wholeMilliseconds == Int64.max)
        #expect(latest.distance(to: earliest).wholeMilliseconds == Int64.min)
    }

    @Test("Execution instant clamps unrepresentable Unix seconds without trapping")
    func validateUnixSecondsInitializerClampsUnrepresentableValues() {
        let instant = OpalFusion.Execution.Instant(unixSeconds: UInt64.max)

        #expect(instant.millisecondsSinceUnixEpoch == Int64.max)
    }
}
