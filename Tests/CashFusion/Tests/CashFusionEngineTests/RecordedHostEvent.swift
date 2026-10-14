// RecordedHostEvent.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
struct RecordedHostEvent: Sendable, Equatable {
    let roundIdentifier: OpalFusion.Round.Identifier?
    let event: OpalFusion.Host.Event
}
