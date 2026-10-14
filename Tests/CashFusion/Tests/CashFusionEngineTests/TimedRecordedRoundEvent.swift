// TimedRecordedRoundEvent.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
import Foundation

struct TimedRecordedRoundEvent: Sendable {
    let roundIdentifier: OpalFusion.Round.Identifier
    let event: OpalFusion.Host.Event
    let recordedAt: Date
}
