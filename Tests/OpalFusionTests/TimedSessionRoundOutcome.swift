// TimedSessionRoundOutcome.swift

@testable import OpalFusion
import Foundation

struct TimedSessionRoundOutcome: Sendable, Equatable {
    let roundIdentifier: OpalFusion.Round.Identifier
    let outcome: SessionRoundOutcomeKind
    let recordedAt: Date
}
