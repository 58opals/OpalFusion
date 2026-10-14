// ScriptedInstantClock.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
actor ScriptedInstantClock {
    private var storedInstant: OpalFusion.Execution.Instant

    init(unixSeconds: UInt64) {
        self.storedInstant = .init(unixSeconds: unixSeconds)
    }

    var current: OpalFusion.Execution.Instant {
        storedInstant
    }

    func update(unixSeconds: UInt64) {
        storedInstant = .init(unixSeconds: unixSeconds)
    }
}
