// RecordedHostEvent.swift

@testable import OpalFusion

struct RecordedHostEvent: Sendable, Equatable {
    let roundIdentifier: OpalFusion.Round.Identifier?
    let event: OpalFusion.Host.Event
}
