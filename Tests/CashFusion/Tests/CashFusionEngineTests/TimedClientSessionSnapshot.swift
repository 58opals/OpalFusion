// TimedClientSessionSnapshot.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
import Foundation

struct TimedClientSessionSnapshot: Sendable {
    let snapshot: OpalFusion.Client.Session.Snapshot
    let recordedAt: Date
}
