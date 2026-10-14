// TimedRoundRequestRecord.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
import Foundation

struct TimedRoundRequestRecord: Sendable {
    let roundIdentifier: OpalFusion.Round.Identifier
    let recordedAt: Date
}
