// OpalFusion+Host+MosaicReservationLease.swift

import Foundation

public extension OpalFusion.Host {
    /// A host-owned, expiring contribution lease created after Mosaic manifest agreement.
    struct MosaicReservationLease: Sendable, Equatable {
        public let reference: MosaicReservationReference
        public let expiresAt: Date
        public let participantReservation: ParticipantReservation

        public init(
            reference: MosaicReservationReference,
            expiresAt: Date,
            participantReservation: ParticipantReservation
        ) throws {
            guard !participantReservation.inputs.isEmpty else {
                throw MosaicHostContractError.emptyReservationInputs
            }
            guard !participantReservation.outputs.isEmpty else {
                throw MosaicHostContractError.emptyReservationOutputs
            }

            self.reference = reference
            self.expiresAt = expiresAt
            self.participantReservation = participantReservation
        }
    }
}
