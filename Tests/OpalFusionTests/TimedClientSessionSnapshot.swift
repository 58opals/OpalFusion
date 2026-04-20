// TimedClientSessionSnapshot.swift

@testable import OpalFusion
import Foundation

struct TimedClientSessionSnapshot: Sendable {
    let snapshot: OpalFusion.Client.Session.Snapshot
    let recordedAt: Date
}
