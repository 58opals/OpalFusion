// OpalFusion+Mosaic+RuntimeCoordinator+DispositionSignal.swift

import Synchronization

final class MosaicRuntimeCoordinatorDispositionGate: Sendable {
    private enum Activity: Sendable, Equatable {
        case idle
        case reservationPublicationClaimed
        case signingClaimed
    }

    private struct Storage: Sendable {
        var isReleaseRequested = false
        var activity = Activity.idle
    }

    private let storage = Mutex(Storage())

    var isReleaseRequested: Bool {
        storage.withLock { $0.isReleaseRequested }
    }

    func observe(_ output: OpalFusion.Mosaic.RuntimeSessionDriver.Output) {
        guard case .runtimeEffect(
            .localAttempt(.walletReservationReleaseRequired)
        ) = output else {
            return
        }
        storage.withLock { $0.isReleaseRequested = true }
    }

    func claimReservationPublication() -> Bool {
        storage.withLock { storage in
            guard !storage.isReleaseRequested,
                  storage.activity == .idle else {
                return false
            }
            storage.activity = .reservationPublicationClaimed
            return true
        }
    }

    func finishReservationPublication() {
        storage.withLock { storage in
            guard storage.activity == .reservationPublicationClaimed else {
                return
            }
            storage.activity = .idle
        }
    }

    func claimSigning() -> Bool {
        storage.withLock { storage in
            guard !storage.isReleaseRequested,
                  storage.activity == .idle else {
                return false
            }
            storage.activity = .signingClaimed
            return true
        }
    }
}
