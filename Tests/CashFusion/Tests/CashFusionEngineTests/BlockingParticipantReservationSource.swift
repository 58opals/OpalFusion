// BlockingParticipantReservationSource.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
actor BlockingParticipantReservationSource: OpalFusion.Host.ParticipantReservationSource {
    private let reservation: OpalFusion.Host.ParticipantReservation
    private var requestedRoundIdentifiers: [OpalFusion.Round.Identifier] = []
    private var releasedResult: Result<OpalFusion.Host.ParticipantReservation, Error>?
    private var reservationContinuation: CheckedContinuation<Result<OpalFusion.Host.ParticipantReservation, Error>, Never>?

    init(
        reservation: OpalFusion.Host.ParticipantReservation
    ) {
        self.reservation = reservation
    }

    func reserveParticipant(
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async throws -> OpalFusion.Host.ParticipantReservation {
        requestedRoundIdentifiers.append(roundIdentifier)
        let result: Result<OpalFusion.Host.ParticipantReservation, Error>
        if let releasedResult {
            result = releasedResult
        } else {
            result = await withCheckedContinuation { continuation in
                reservationContinuation = continuation
            }
        }

        switch result {
        case let .success(reservation):
            return reservation
        case let .failure(error):
            throw error
        }
    }

    var requestedRounds: [OpalFusion.Round.Identifier] {
        requestedRoundIdentifiers
    }

    func releaseReservation(
        _ reservation: OpalFusion.Host.ParticipantReservation? = nil
    ) {
        let result: Result<OpalFusion.Host.ParticipantReservation, Error> = .success(
            reservation ?? self.reservation
        )
        releasedResult = result
        reservationContinuation?.resume(returning: result)
        reservationContinuation = nil
    }

    func failReservation(
        _ error: Error
    ) {
        releasedResult = .failure(error)
        reservationContinuation?.resume(returning: .failure(error))
        reservationContinuation = nil
    }
}
