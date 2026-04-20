// TimedRecordedRoundEvent.swift

@testable import OpalFusion
import Foundation

struct TimedRecordedRoundEvent: Sendable {
    let roundIdentifier: OpalFusion.Round.Identifier
    let event: OpalFusion.Host.Event
    let recordedAt: Date
}
