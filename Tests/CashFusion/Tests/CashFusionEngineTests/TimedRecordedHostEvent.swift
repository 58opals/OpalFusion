// TimedRecordedHostEvent.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
import Foundation

struct TimedRecordedHostEvent: Sendable {
    let roundIdentifier: OpalFusion.Round.Identifier?
    let event: OpalFusion.Host.Event
    let recordedAt: Date
}
