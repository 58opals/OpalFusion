// ScriptedNowProvider.swift

@testable import OpalFusion

actor ScriptedNowProvider {
    private var currentInstant: OpalFusion.Execution.Instant

    init(unixSeconds: UInt64) {
        self.currentInstant = .init(unixSeconds: unixSeconds)
    }

    func now() -> OpalFusion.Execution.Instant {
        return currentInstant
    }

    func set(unixSeconds: UInt64) {
        currentInstant = .init(unixSeconds: unixSeconds)
    }
}
