// MosaicPrivateAlphaRuntimePersistenceStore.swift

import Foundation
import Synchronization
@_spi(MosaicPrivateAlpha) import OpalFusion

final class MosaicPrivateAlphaRuntimePersistenceStore: Sendable {
    typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime

    private let values = Mutex<[Runtime.Binding: Data]>([:])
    private let compareAndSwapFailureCount = Mutex(0)
    private let compareAndSwapPostWriteFailureCount = Mutex(0)
    private let compareAndSwapCallCount = Mutex(0)
    private let provisionCallCount = Mutex(0)

    func load(_ binding: Runtime.Binding) -> Data? {
        values.withLock { $0[binding] }
    }

    func compareAndSwap(
        _ binding: Runtime.Binding,
        _ expected: Data?,
        _ replacement: Data
    ) throws -> Data {
        compareAndSwapCallCount.withLock { $0 += 1 }
        if compareAndSwapFailureCount.withLock({ count in
            if count > 0 {
                count -= 1
                return true
            }
            return false
        }) {
                throw Runtime.Failure.exactReadbackMismatch
        }
        let readback = try values.withLock { values in
            guard values[binding] == expected else {
                throw Runtime.Failure.staleRecoveryTransition
            }
            values[binding] = replacement
            return replacement
        }
        if compareAndSwapPostWriteFailureCount.withLock({ count in
            guard count > 0 else { return false }
            count -= 1
            return true
        }) {
            throw Runtime.Failure.exactReadbackMismatch
        }
        return readback
    }

    func failNextCompareAndSwap() {
        compareAndSwapFailureCount.withLock { $0 += 1 }
    }

    func failNextCompareAndSwapAfterWriting() {
        compareAndSwapPostWriteFailureCount.withLock { $0 += 1 }
    }

    func remove(_ binding: Runtime.Binding) {
        values.withLock { $0[binding] = nil }
    }

    func recordProvisionCall() {
        provisionCallCount.withLock { $0 += 1 }
    }

    var recordedProvisionCallCount: Int {
        provisionCallCount.withLock { $0 }
    }

    var recordedCompareAndSwapCallCount: Int {
        compareAndSwapCallCount.withLock { $0 }
    }
}
