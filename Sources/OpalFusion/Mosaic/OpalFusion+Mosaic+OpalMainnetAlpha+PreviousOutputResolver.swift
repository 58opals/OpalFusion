// OpalFusion+Mosaic+OpalMainnetAlpha+PreviousOutputResolver.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Resolves the previous outputs committed by one exact mainnet-alpha transcript.
    ///
    /// Resolution supplies transaction data only. It does not authorize BCH signing, host
    /// commit, transport publication, or broadcast.
    struct PreviousOutputResolver: Sendable {
        enum Failure: Error, Sendable, Equatable {
            case unsupportedProfile(OpalFusion.Mosaic.Profile)
            case invalidTranscriptInput
            case sourceRejected
            case outputCountMismatch(expected: Int, actual: Int)
            case outputMismatch(index: Int)
            case tokenBearingOutput(index: Int)
        }

        struct Validation: Sendable, Equatable {
            let transcriptRoot: OpalFusion.Mosaic.Attempt.TranscriptRoot
            let spentInputs: [OpalFusion.Host.ParticipantInput]
        }

        private let source: any OpalFusion.Host.MosaicPreviousOutputSource

        init(source: any OpalFusion.Host.MosaicPreviousOutputSource) {
            self.source = source
        }

        func resolve(
            for transcript: OpalFusion.Mosaic.OpalV0
                .UnsignedTransactionTranscript
        ) async throws -> Validation {
            guard transcript.profile == .opalMainnetAlpha else {
                throw Failure.unsupportedProfile(transcript.profile)
            }
            let requests: [OpalFusion.Host.MosaicPreviousOutputRequest]
            do {
                let inputComponents: [OpalFusion.Mosaic.OpalV0.InputComponent]
                    = transcript.componentSet.components.compactMap { component in
                    guard case let .input(input) = component.payload else {
                        return nil
                    }
                    return input
                }
                requests = try inputComponents.sorted { lhs, rhs in
                    if lhs.previousTransactionHash
                        != rhs.previousTransactionHash {
                        return lhs.previousTransactionHash
                            .lexicographicallyPrecedes(
                                rhs.previousTransactionHash
                            )
                    }
                    return lhs.outputIndex < rhs.outputIndex
                }.map {
                    try .init(
                        transactionHashBytes: $0.previousTransactionHash,
                        outputIndex: $0.outputIndex,
                        expectedAmountSatoshis: $0.amountSatoshis
                    )
                }
            } catch {
                throw Failure.invalidTranscriptInput
            }
            guard !requests.isEmpty else {
                throw Failure.invalidTranscriptInput
            }

            try Task.checkCancellation()
            let resolvedOutputs: [OpalFusion.Host.MosaicPreviousOutput]
            do {
                resolvedOutputs = try await source.resolvePreviousOutputs(
                    for: requests
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                throw Failure.sourceRejected
            }
            try Task.checkCancellation()
            guard resolvedOutputs.count == requests.count else {
                throw Failure.outputCountMismatch(
                    expected: requests.count,
                    actual: resolvedOutputs.count
                )
            }
            let spentInputs: [OpalFusion.Host.ParticipantInput]
            spentInputs = try zip(requests, resolvedOutputs).enumerated().map {
                index, pair in
                let request = pair.0
                let output = pair.1
                guard output.transactionHashBytes
                        == request.transactionHashBytes,
                      output.outputIndex == request.outputIndex,
                      output.amountSatoshis
                        == request.expectedAmountSatoshis else {
                    throw Failure.outputMismatch(index: index)
                }
                guard output.tokenState == .absent else {
                    throw Failure.tokenBearingOutput(index: index)
                }
                return OpalFusion.Host.ParticipantInput(
                    outpointTransactionHashBytes:
                        output.transactionHashBytes,
                    outpointIndex: output.outputIndex,
                    amountSatoshis: output.amountSatoshis,
                    lockingScriptBytes: output.lockingScriptBytes
                )
            }
            return .init(
                transcriptRoot: transcript.transcriptRoot,
                spentInputs: spentInputs
            )
        }
    }
}
