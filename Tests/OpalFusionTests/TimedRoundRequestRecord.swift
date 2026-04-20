// TimedRoundRequestRecord.swift

@testable import OpalFusion
import Foundation

struct TimedRoundRequestRecord: Sendable {
    let roundIdentifier: OpalFusion.Round.Identifier
    let recordedAt: Date
}
