// OpalFusion+Mosaic+OpalMainnetAlpha+CompleteTransactionValidation.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// One exact signature-set and complete-transaction publication awaiting authoritative
    /// previous-output validation.
    struct CompleteTransactionCandidate: Sendable, Equatable {
        typealias AttemptIdentifier = OpalFusion.Mosaic.LocalAttempt.AttemptIdentifier
        typealias GenerationIdentifier = OpalFusion.Mosaic.LocalAttempt.GenerationIdentifier
        typealias MaterialIdentifier = OpalFusion.Mosaic.LocalAttempt.MaterialIdentifier

        let attemptIdentifier: AttemptIdentifier
        let generationIdentifier: GenerationIdentifier
        let materialIdentifier: MaterialIdentifier
        let transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
        let signatureSet: BCHSignatureSet
        let payload: CompleteTransactionPayload

        init(
            attemptIdentifier: AttemptIdentifier,
            generationIdentifier: GenerationIdentifier,
            materialIdentifier: MaterialIdentifier,
            transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript,
            signatureSet: BCHSignatureSet,
            payload: CompleteTransactionPayload
        ) throws {
            guard transcript.profile == .opalMainnetAlpha,
                  signatureSet.roundIdentifier
                    == transcript.manifest.roundIdentifier,
                  signatureSet.transcriptRoot
                    == transcript.transcriptRoot.validatedBytes,
                  payload.matches(transcript: transcript),
                  payload.roundIdentifier == signatureSet.roundIdentifier,
                  payload.transcriptRoot == signatureSet.transcriptRoot,
                  payload.transaction.inputs.count == signatureSet.entries.count else {
                throw ContractError.transactionMismatch
            }
            for (index, entry) in signatureSet.entries.enumerated() {
                let expectedUnlockingScript = [UInt8(0x41)]
                    + entry.signature
                    + [UInt8(0x41), UInt8(0x21)]
                    + entry.publicKey
                guard entry.inputIndex == UInt32(index),
                      payload.transaction.inputs[index].unlockingScript
                        == expectedUnlockingScript else {
                    throw ContractError.transactionMismatch
                }
            }
            self.attemptIdentifier = attemptIdentifier
            self.generationIdentifier = generationIdentifier
            self.materialIdentifier = materialIdentifier
            self.transcript = transcript
            self.signatureSet = signatureSet
            self.payload = payload
        }
    }

    /// Seals byte-exact complete-transaction assembly to one routed runtime candidate.
    struct CompleteTransactionValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case previousOutputTranscriptMismatch
            case assemblyFailed
        }

        let candidate: CompleteTransactionCandidate
        let completeTransaction: OpalFusion.Host.MosaicCompleteTransaction

        init(
            validating candidate: CompleteTransactionCandidate,
            previousOutputs: PreviousOutputResolver.Validation
        ) throws(ValidationError) {
            guard previousOutputs.transcriptRoot
                == candidate.transcript.transcriptRoot else {
                throw .previousOutputTranscriptMismatch
            }
            let completeTransaction: OpalFusion.Host.MosaicCompleteTransaction
            do {
                completeTransaction = try CompleteTransactionAssembler.assemble(
                    transcript: candidate.transcript,
                    signatureSet: candidate.signatureSet,
                    spentInputs: previousOutputs.spentInputs
                )
            } catch {
                throw .assemblyFailed
            }
            // Candidate construction already binds every unlocking script and the unsigned body
            // to the published canonical transaction. Assembly supplies the remaining
            // previous-output-backed cryptographic authority.
            self.candidate = candidate
            self.completeTransaction = completeTransaction
        }
    }

    /// Candidate-bound negative result from authoritative previous-output or exact-byte
    /// validation. Binding prevents a stale asynchronous failure from terminating new material.
    struct CompleteTransactionValidationRejection: Sendable, Equatable {
        enum Reason: Sendable, Equatable {
            case previousOutputResolutionFailed
            case exactTransactionValidationFailed
        }

        let candidate: CompleteTransactionCandidate
        let reason: Reason

        init(
            candidate: CompleteTransactionCandidate,
            reason: Reason
        ) {
            self.candidate = candidate
            self.reason = reason
        }
    }
}
