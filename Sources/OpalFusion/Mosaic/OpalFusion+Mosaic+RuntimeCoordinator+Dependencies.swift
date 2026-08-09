// OpalFusion+Mosaic+RuntimeCoordinator+Dependencies.swift

extension OpalFusion.Mosaic.RuntimeCoordinator {
    struct AttemptContext: Sendable, Equatable {
        let attemptIdentifier: OpalFusion.Mosaic.LocalAttempt.AttemptIdentifier
        let generationIdentifier: OpalFusion.Mosaic.LocalAttempt.GenerationIdentifier
        let materialIdentifier: OpalFusion.Mosaic.LocalAttempt.MaterialIdentifier
        let contributor: OpalFusion.Mosaic.Attempt.ControlIdentity
        let profile: OpalFusion.Mosaic.Profile
    }

    struct ReservationEligibility: Sendable, Equatable {
        let context: AttemptContext
        let manifest: OpalFusion.Mosaic.Attempt.ManifestBinding
    }

    struct TranscriptInclusionRequest: Sendable, Equatable {
        let context: AttemptContext
        let transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
    }

    struct PreSignPublication: Sendable, Equatable {
        let context: AttemptContext
        let roundIdentifier: [UInt8]
        let transcriptRoot: OpalFusion.Mosaic.Attempt.TranscriptRoot
    }

    struct SigningEligibility: Sendable, Equatable {
        let context: AttemptContext
        let transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
    }

    struct CommitEligibility: Sendable, Equatable {
        let context: AttemptContext
    }

    struct Dependencies: Sendable {
        typealias InputStream = OpalFusion.Mosaic.RuntimeSessionDriver
            .Dependencies.InputStream
        typealias OpenInputStream = @Sendable () async throws -> InputStream
        typealias CloseInputSource = @Sendable () async -> Void

        let transactionHost: any OpalFusion.Host.MosaicCompleteTransactionHost
        let openInputStream: OpenInputStream
        let closeInputSource: CloseInputSource
        let makeReservationRequest: @Sendable (
            ReservationEligibility
        ) async throws -> OpalFusion.Host.MosaicReservationRequest
        let publishReservedContribution: @Sendable (
            ReservationEligibility,
            OpalFusion.Host.MosaicReservationLease
        ) async throws -> Void
        let validateTranscriptInclusion: @Sendable (
            TranscriptInclusionRequest
        ) async throws -> OpalFusion.Mosaic.LocalAttempt
            .TranscriptInclusionValidation
        let publishPreSignAcknowledgement: @Sendable (
            PreSignPublication
        ) async throws -> Void
        let makeSigningRequest: @Sendable (
            SigningEligibility,
            OpalFusion.Host.MosaicReservationLease
        ) async throws -> OpalFusion.Host.MosaicTransactionSigningRequest
        let validateAndPublishLocalSignatures: @Sendable (
            SigningEligibility,
            OpalFusion.Host.MosaicTransactionSigningRequest,
            OpalFusion.Host.FinalizedTransaction
        ) async throws -> Void
        let loadValidatedCompleteTransaction: @Sendable (
            CommitEligibility,
            OpalFusion.Host.MosaicReservationLease
        ) async throws -> OpalFusion.Host.MosaicCompleteTransaction

        init(
            transactionHost: any OpalFusion.Host.MosaicCompleteTransactionHost,
            openInputStream: @escaping OpenInputStream,
            closeInputSource: @escaping CloseInputSource,
            makeReservationRequest: @escaping @Sendable (
                ReservationEligibility
            ) async throws -> OpalFusion.Host.MosaicReservationRequest,
            publishReservedContribution: @escaping @Sendable (
                ReservationEligibility,
                OpalFusion.Host.MosaicReservationLease
            ) async throws -> Void,
            validateTranscriptInclusion: @escaping @Sendable (
                TranscriptInclusionRequest
            ) async throws -> OpalFusion.Mosaic.LocalAttempt
                .TranscriptInclusionValidation,
            publishPreSignAcknowledgement: @escaping @Sendable (
                PreSignPublication
            ) async throws -> Void,
            makeSigningRequest: @escaping @Sendable (
                SigningEligibility,
                OpalFusion.Host.MosaicReservationLease
            ) async throws -> OpalFusion.Host.MosaicTransactionSigningRequest,
            validateAndPublishLocalSignatures: @escaping @Sendable (
                SigningEligibility,
                OpalFusion.Host.MosaicTransactionSigningRequest,
                OpalFusion.Host.FinalizedTransaction
            ) async throws -> Void,
            loadValidatedCompleteTransaction: @escaping @Sendable (
                CommitEligibility,
                OpalFusion.Host.MosaicReservationLease
            ) async throws -> OpalFusion.Host.MosaicCompleteTransaction
        ) {
            self.transactionHost = transactionHost
            self.openInputStream = openInputStream
            self.closeInputSource = closeInputSource
            self.makeReservationRequest = makeReservationRequest
            self.publishReservedContribution = publishReservedContribution
            self.validateTranscriptInclusion = validateTranscriptInclusion
            self.publishPreSignAcknowledgement = publishPreSignAcknowledgement
            self.makeSigningRequest = makeSigningRequest
            self.validateAndPublishLocalSignatures = validateAndPublishLocalSignatures
            self.loadValidatedCompleteTransaction = loadValidatedCompleteTransaction
        }
    }
}
