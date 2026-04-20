// RecordedRoundEvent.swift

@testable import OpalFusion

struct RecordedRoundEvent: Sendable, Equatable {
    let roundIdentifier: OpalFusion.Round.Identifier
    let event: OpalFusion.Host.Event
}
