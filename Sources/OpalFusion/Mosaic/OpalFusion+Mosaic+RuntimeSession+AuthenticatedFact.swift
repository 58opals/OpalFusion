// OpalFusion+Mosaic+RuntimeSession+AuthenticatedFact.swift

extension OpalFusion.Mosaic.RuntimeSession {
    /// A protocol fact permitted to cross the outer-authenticated network boundary.
    ///
    /// Local cancellation, retry, and wallet-host results are intentionally absent. Embedded
    /// manifest and transcript signatures remain unverified until the runtime validates them
    /// after replay and phase checks.
    enum AuthenticatedFact: Sendable, Equatable {
        case manifestSignatureSet(
            binding: OpalFusion.Mosaic.Attempt.ManifestBinding,
            signatures: [OpalFusion.Mosaic.Attempt.ManifestSignature]
        )
        case groupedCommitmentsValidated(
            contributors: [OpalFusion.Mosaic.Attempt.ControlIdentity]
        )
        case anonymousComponentsValidated(
            contributors: [OpalFusion.Mosaic.Attempt.ControlIdentity]
        )
        case transcriptAcknowledgementSet(
            [OpalFusion.Mosaic.Attempt.TranscriptAcknowledgement]
        )
        case abort(OpalFusion.Mosaic.Attempt.AbortReason)

        func attemptInput(
            expectedManifestSignatureCount: Int,
            expectedTranscriptAcknowledgementCount: Int,
            transcriptAcknowledgementProfile: OpalFusion.Mosaic.Profile
        ) throws(OpalFusion.Mosaic.RuntimeSession.Failure)
            -> OpalFusion.Mosaic.Attempt.Input {
            switch self {
            case let .manifestSignatureSet(binding, signatures):
                guard signatures.count == expectedManifestSignatureCount else {
                    throw .invalidManifestSignatureCount(
                        expected: expectedManifestSignatureCount,
                        actual: signatures.count
                    )
                }
                var validations: [
                    OpalFusion.Mosaic.Attempt.ManifestSignatureValidation
                ] = []
                validations.reserveCapacity(signatures.count)
                for signature in signatures {
                    do {
                        validations.append(
                            try .init(validating: signature, for: binding)
                        )
                    } catch {
                        throw .invalidManifestSignature(error)
                    }
                }
                return .manifestSignaturesValidated(validations)
            case let .groupedCommitmentsValidated(contributors):
                return .groupedCommitmentsValidated(contributors: contributors)
            case let .anonymousComponentsValidated(contributors):
                return .anonymousComponentsValidated(contributors: contributors)
            case let .transcriptAcknowledgementSet(acknowledgements):
                guard acknowledgements.count
                    == expectedTranscriptAcknowledgementCount else {
                    throw .invalidTranscriptAcknowledgementCount(
                        expected: expectedTranscriptAcknowledgementCount,
                        actual: acknowledgements.count
                    )
                }
                var validations: [
                    OpalFusion.Mosaic.Attempt.TranscriptAcknowledgementValidation
                ] = []
                validations.reserveCapacity(acknowledgements.count)
                for acknowledgement in acknowledgements {
                    do {
                        validations.append(
                            try .init(
                                validating: acknowledgement,
                                profile: transcriptAcknowledgementProfile
                            )
                        )
                    } catch {
                        throw .invalidTranscriptAcknowledgement(error)
                    }
                }
                return .transcriptAgreementValidated(validations)
            case let .abort(reason):
                return .abort(reason)
            }
        }
    }
}
