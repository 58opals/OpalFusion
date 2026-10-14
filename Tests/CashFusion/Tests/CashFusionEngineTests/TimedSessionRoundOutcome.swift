// TimedSessionRoundOutcome.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
import Foundation

struct TimedSessionRoundOutcome: Sendable, Equatable {
    let roundIdentifier: OpalFusion.Round.Identifier
    let outcome: SessionRoundOutcomeKind
    let recordedAt: Date
}
