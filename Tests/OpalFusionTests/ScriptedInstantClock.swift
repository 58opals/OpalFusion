// ScriptedInstantClock.swift

@testable import OpalFusion

actor ScriptedInstantClock {
    private var currentInstant: OpalFusion.Execution.Instant

    init(unixSeconds: UInt64) {
        self.currentInstant = .init(unixSeconds: unixSeconds)
    }

    func now() -> OpalFusion.Execution.Instant {
        return currentInstant
    }

    func update(unixSeconds: UInt64) {
        currentInstant = .init(unixSeconds: unixSeconds)
    }
}
