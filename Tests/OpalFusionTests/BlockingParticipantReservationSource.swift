// BlockingParticipantReservationSource.swift

@testable import OpalFusion

actor BlockingParticipantReservationSource: OpalFusion.Host.ParticipantReservationSource {
    private let reservation: OpalFusion.Host.ParticipantReservation
    private var requestedRoundIdentifiers: [OpalFusion.Round.Identifier] = []
    private var reservationContinuation: CheckedContinuation<Result<OpalFusion.Host.ParticipantReservation, Error>, Never>?

    init(
        reservation: OpalFusion.Host.ParticipantReservation
    ) {
        self.reservation = reservation
    }

    func participantReservation(
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async throws -> OpalFusion.Host.ParticipantReservation {
        requestedRoundIdentifiers.append(roundIdentifier)
        let result = await withCheckedContinuation { continuation in
            reservationContinuation = continuation
        }

        switch result {
        case let .success(reservation):
            return reservation
        case let .failure(error):
            throw error
        }
    }

    func requestedRounds() -> [OpalFusion.Round.Identifier] {
        requestedRoundIdentifiers
    }

    func releaseReservation(
        _ reservation: OpalFusion.Host.ParticipantReservation? = nil
    ) {
        reservationContinuation?.resume(returning: .success(reservation ?? self.reservation))
        reservationContinuation = nil
    }

    func failReservation(
        _ error: Error
    ) {
        reservationContinuation?.resume(returning: .failure(error))
        reservationContinuation = nil
    }
}
