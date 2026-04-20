// ScriptedNowProvider.swift

@testable import OpalFusion
import Foundation

final class ScriptedNowProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var currentInstant: OpalFusion.Execution.Instant

    init(unixSeconds: UInt64) {
        self.currentInstant = .init(unixSeconds: unixSeconds)
    }

    func now() -> OpalFusion.Execution.Instant {
        lock.lock()
        defer { lock.unlock() }
        return currentInstant
    }

    func set(unixSeconds: UInt64) {
        lock.lock()
        currentInstant = .init(unixSeconds: unixSeconds)
        lock.unlock()
    }
}
