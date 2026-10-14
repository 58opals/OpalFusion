// RecordedRoundEvent.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
struct RecordedRoundEvent: Sendable, Equatable {
    let roundIdentifier: OpalFusion.Round.Identifier
    let event: OpalFusion.Host.Event
}
