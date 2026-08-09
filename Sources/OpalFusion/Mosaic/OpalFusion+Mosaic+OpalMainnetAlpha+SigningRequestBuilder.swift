// OpalFusion+Mosaic+OpalMainnetAlpha+SigningRequestBuilder.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Constructs one exact host signing request from already-validated runtime material.
    ///
    /// This boundary neither authorizes signing nor resolves previous outputs. The caller must
    /// supply the accepted reservation-publication proof, exact local transcript-inclusion proof,
    /// roster-complete acknowledgement set, and transcript-bound output of
    /// `PreviousOutputResolver`; the wallet host remains responsible for its independent checks.
    enum SigningRequestBuilder {
        enum Failure: Error, Sendable, Equatable {
            case unsupportedProfile(OpalFusion.Mosaic.Profile)
            case localPeerIsNotContributor
            case contextBindingMismatch
            case reservationPublicationMismatch
            case transcriptInclusionMismatch
            case acknowledgementSetMismatch
            case manifestMismatch
            case previousOutputTranscriptMismatch
            case duplicateLocalInput(index: Int)
            case localInputMissing(index: Int)
            case localInputAmountMismatch(index: Int)
            case localInputLockingScriptMismatch(index: Int)
            case localInputPublicKeyMissing(index: Int)
            case invalidLocalP2PKHLockingScript(index: Int)
            case localOutputMissing(index: Int)
            case requestConstructionFailed
        }

        private struct Outpoint: Hashable {
            let transactionHash: [UInt8]
            let outputIndex: UInt32
        }

        private struct Output: Hashable {
            let lockingScript: [UInt8]
            let amountSatoshis: UInt64
        }

        static func build(
            context: RuntimeSession.Context,
            reservationPublication: RuntimeSession
                .ReservationPublicationValidation,
            transcriptInclusion: OpalFusion.Mosaic.LocalAttempt
                .TranscriptInclusionValidation,
            acknowledgementSet: PreSignAcknowledgementSet,
            previousOutputs: PreviousOutputResolver.Validation
        ) throws(Failure) -> OpalFusion.Host.MosaicTransactionSigningRequest {
            let publication = reservationPublication.request
            let manifest = publication.manifest
            let lease = publication.reservationLease
            let transcript = transcriptInclusion.transcript
            guard transcript.profile == .opalMainnetAlpha else {
                throw .unsupportedProfile(transcript.profile)
            }
            guard context.localRole == .contributor else {
                throw .localPeerIsNotContributor
            }
            guard context.roster == manifest.core.roster else {
                throw .contextBindingMismatch
            }

            guard publication.attemptIdentifier == context.attemptIdentifier,
                  publication.generationIdentifier
                    == context.generationIdentifier,
                  publication.materialIdentifier == context.materialIdentifier,
                  publication.contributor == context.localControlIdentity else {
                throw .contextBindingMismatch
            }
            guard publication.playerCommit.contributor
                    == context.localControlIdentity,
                  publication.playerCommit.roundIdentifier
                    == manifest.core.roundIdentifier else {
                throw .reservationPublicationMismatch
            }
            guard transcriptInclusion.attemptIdentifier
                    == context.attemptIdentifier,
                  transcriptInclusion.generationIdentifier
                    == context.generationIdentifier,
                  transcriptInclusion.materialIdentifier
                    == context.materialIdentifier,
                  transcriptInclusion.contributor
                    == context.localControlIdentity else {
                throw .transcriptInclusionMismatch
            }
            guard transcript.manifest == manifest.binding,
                  transcript.contributors == context.roster.contributors else {
                throw .manifestMismatch
            }
            let acknowledgedContributors = acknowledgementSet.submissions.map {
                $0.acknowledgement.contributor
            }
            guard acknowledgementSet.roundIdentifier
                    == manifest.core.roundIdentifier,
                  acknowledgementSet.transcriptRoot
                    == transcript.transcriptRoot.validatedBytes,
                  acknowledgedContributors
                    == manifest.core.orderedContributors else {
                throw .acknowledgementSetMismatch
            }
            guard previousOutputs.transcriptRoot == transcript.transcriptRoot else {
                throw .previousOutputTranscriptMismatch
            }

            var inputIndexByOutpoint: [Outpoint: Int] = [:]
            for (index, spentInput) in previousOutputs.spentInputs.enumerated() {
                inputIndexByOutpoint[
                    .init(
                        transactionHash:
                            spentInput.outpointTransactionHashBytes,
                        outputIndex: spentInput.outpointIndex
                    )
                ] = index
            }

            var requestSpentInputs = previousOutputs.spentInputs
            var localInputIndices: [Int] = []
            var seenLocalOutpoints: Set<Outpoint> = []
            for (reservationIndex, localInput) in lease
                .participantReservation.inputs.enumerated() {
                let outpoint = Outpoint(
                    transactionHash: localInput.outpointTransactionHashBytes,
                    outputIndex: localInput.outpointIndex
                )
                guard seenLocalOutpoints.insert(outpoint).inserted else {
                    throw .duplicateLocalInput(index: reservationIndex)
                }
                guard let transactionIndex = inputIndexByOutpoint[outpoint] else {
                    throw .localInputMissing(index: reservationIndex)
                }
                let authoritativeInput = requestSpentInputs[transactionIndex]
                guard localInput.amountSatoshis
                        == authoritativeInput.amountSatoshis else {
                    throw .localInputAmountMismatch(index: reservationIndex)
                }
                guard localInput.lockingScriptBytes
                        == authoritativeInput.lockingScriptBytes else {
                    throw .localInputLockingScriptMismatch(index: reservationIndex)
                }
                guard let publicKey = localInput.publicKey else {
                    throw .localInputPublicKeyMissing(index: reservationIndex)
                }
                guard OpalFusion.Execution.ProtocolPrimitives
                    .isCompressedSecp256k1PublicKey(publicKey),
                    OpalFusion.Execution.ProtocolPrimitives
                    .isStandardP2PKHLockingScript(
                    localInput.lockingScriptBytes,
                    publicKey: publicKey
                    ) else {
                    throw .invalidLocalP2PKHLockingScript(
                        index: reservationIndex
                    )
                }
                requestSpentInputs[transactionIndex] = .init(
                    outpointTransactionHashBytes:
                        authoritativeInput.outpointTransactionHashBytes,
                    outpointIndex: authoritativeInput.outpointIndex,
                    amountSatoshis: authoritativeInput.amountSatoshis,
                    lockingScriptBytes: authoritativeInput.lockingScriptBytes,
                    publicKey: publicKey
                )
                localInputIndices.append(transactionIndex)
            }
            localInputIndices.sort()

            var availableOutputs: [Output: Int] = [:]
            for output in transcript.transaction.outputs {
                availableOutputs[
                    .init(
                        lockingScript: output.lockingScript,
                        amountSatoshis: output.amountSatoshis
                    ),
                    default: 0
                ] += 1
            }
            for (reservationIndex, localOutput) in lease
                .participantReservation.outputs.enumerated() {
                let output = Output(
                    lockingScript: localOutput.lockingScriptBytes,
                    amountSatoshis: localOutput.amountSatoshis
                )
                guard let availableCount = availableOutputs[output],
                      availableCount > 0 else {
                    throw .localOutputMissing(index: reservationIndex)
                }
                availableOutputs[output] = availableCount - 1
            }

            let requiredExcessFeeSatoshis: UInt64
            do {
                requiredExcessFeeSatoshis = try ContributionFeePolicy
                    .requiredExcessFeeSatoshis(
                        for: context.localControlIdentity,
                        in: context.roster
                    )
            } catch {
                throw .contextBindingMismatch
            }

            do {
                return try .init(
                    reservationReference: lease.reference,
                    roundIdentifier: manifest.core.roundIdentifier,
                    transcriptBinding: transcript.transcriptBinding,
                    unsignedTransactionBytes: transcript
                        .unsignedTransactionBytes,
                    spentInputs: requestSpentInputs,
                    localInputIndices: localInputIndices,
                    expectedLocalOutputs: lease.participantReservation.outputs,
                    feeRateSatoshisPerByte:
                        manifest.core.feeRateSatoshisPerByte,
                    minimumExcessFeeSatoshis:
                        manifest.core.minimumExcessFeeSatoshis,
                    maximumExcessFeeSatoshis:
                        manifest.core.maximumExcessFeeSatoshis,
                    requiredExcessFeeSatoshis: requiredExcessFeeSatoshis,
                    transactionProfileIdentifier:
                        manifest.core.transactionProfileIdentifier
                )
            } catch {
                throw .requestConstructionFailed
            }
        }

    }
}
