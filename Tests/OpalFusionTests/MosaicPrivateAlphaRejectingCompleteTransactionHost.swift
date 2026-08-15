// MosaicPrivateAlphaRejectingCompleteTransactionHost.swift

@_spi(MosaicPrivateAlpha) @testable import OpalFusion

actor MosaicPrivateAlphaRejectingCompleteTransactionHost:
    OpalFusion.Host.MosaicCompleteTransactionHost {
    func reserveMosaicContribution(
        for _: OpalFusion.Host.MosaicReservationRequest
    ) async throws -> OpalFusion.Host.MosaicReservationLease {
        throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
            .invalidStateTransition
    }

    func finalizeMosaicTransaction(
        for _: OpalFusion.Host.MosaicTransactionSigningRequest
    ) async throws -> OpalFusion.Host.FinalizedTransaction {
        throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
            .invalidStateTransition
    }

    func releaseMosaicReservation(
        _: OpalFusion.Host.MosaicReservationReference
    ) async throws {
        throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
            .invalidStateTransition
    }

    func commitMosaicReservation(
        _: OpalFusion.Host.MosaicReservationReference,
        finalizedTransaction _: OpalFusion.Host.FinalizedTransaction
    ) async throws {
        throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
            .invalidStateTransition
    }

    func commitMosaicReservation(
        _: OpalFusion.Host.MosaicReservationReference,
        completeTransaction _: OpalFusion.Host.MosaicCompleteTransaction
    ) async throws {
        throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
            .invalidStateTransition
    }
}
