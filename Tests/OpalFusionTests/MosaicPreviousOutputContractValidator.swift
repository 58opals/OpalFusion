// MosaicPreviousOutputContractValidator.swift

import Foundation
import Testing
@testable import OpalFusion

@Suite("Mosaic previous-output contract")
struct MosaicPreviousOutputContractValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Host = OpalFusion.Host

    private actor SourceProbe: Host.MosaicPreviousOutputSource {
        enum Mode: Sendable {
            case valid
            case reject
            case substitutedHash
            case substitutedIndex
            case substitutedAmount
            case reversed
            case tokenBearing
            case wrongCount
            case cancel
        }

        enum ProbeError: Error {
            case rejected
        }

        private let mode: Mode
        private let suspension: MosaicRuntimeCoordinatorSuspensionProbe?
        private(set) var receivedRequests: [[Host.MosaicPreviousOutputRequest]]
            = []

        init(
            mode: Mode = .valid,
            suspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil
        ) {
            self.mode = mode
            self.suspension = suspension
        }

        func resolvePreviousOutputs(
            for requests: [Host.MosaicPreviousOutputRequest]
        ) async throws -> [Host.MosaicPreviousOutput] {
            receivedRequests.append(requests)
            await suspension?.suspendIfArmed()
            switch mode {
            case .valid:
                return try requests.map { try Self.output(for: $0) }
            case .reject:
                throw ProbeError.rejected
            case .substitutedHash:
                var hash = requests[0].transactionHashBytes
                hash[0] ^= 0x01
                return [
                    try Host.MosaicPreviousOutput(
                        transactionHashBytes: hash,
                        outputIndex: requests[0].outputIndex,
                        amountSatoshis:
                            requests[0].expectedAmountSatoshis,
                        lockingScriptBytes:
                            MosaicUnsignedTransactionTranscriptFixtures
                                .p2pkhLockingScript(fill: 0x66),
                        tokenState: .absent
                    ),
                ]
            case .substitutedIndex:
                return [
                    try Host.MosaicPreviousOutput(
                        transactionHashBytes:
                            requests[0].transactionHashBytes,
                        outputIndex: requests[0].outputIndex + 1,
                        amountSatoshis:
                            requests[0].expectedAmountSatoshis,
                        lockingScriptBytes:
                            MosaicUnsignedTransactionTranscriptFixtures
                                .p2pkhLockingScript(fill: 0x66),
                        tokenState: .absent
                    ),
                ]
            case .substitutedAmount:
                return [
                    try Host.MosaicPreviousOutput(
                        transactionHashBytes:
                            requests[0].transactionHashBytes,
                        outputIndex: requests[0].outputIndex,
                        amountSatoshis:
                            requests[0].expectedAmountSatoshis + 1,
                        lockingScriptBytes:
                            MosaicUnsignedTransactionTranscriptFixtures
                                .p2pkhLockingScript(fill: 0x66),
                        tokenState: .absent
                    ),
                ]
            case .reversed:
                return try requests.reversed().map {
                    try Self.output(for: $0)
                }
            case .tokenBearing:
                return try requests.map {
                    try Self.output(for: $0, tokenState: .present)
                }
            case .wrongCount:
                return []
            case .cancel:
                throw CancellationError()
            }
        }

        private static func output(
            for request: Host.MosaicPreviousOutputRequest,
            tokenState: Host.MosaicPreviousOutputTokenState = .absent
        ) throws -> Host.MosaicPreviousOutput {
            try .init(
                transactionHashBytes: request.transactionHashBytes,
                outputIndex: request.outputIndex,
                amountSatoshis: request.expectedAmountSatoshis,
                lockingScriptBytes:
                    MosaicUnsignedTransactionTranscriptFixtures
                        .p2pkhLockingScript(fill: 0x66),
                tokenState: tokenState
            )
        }
    }

    enum ResolvedOutputSubstitution: CaseIterable, Sendable {
        case transactionHashLength
        case amount
        case lockingScript
    }

    enum BindingSubstitution: CaseIterable, Sendable {
        case transactionHash
        case outputIndex
        case amount
        case order
    }

    @Test("Request validates exact outpoint and expected amount")
    func validateRequest() throws {
        let request = try makeRequest()
        #expect(request.transactionHashBytes == [UInt8](repeating: 0x31, count: 32))
        #expect(request.outputIndex == 4)
        #expect(request.expectedAmountSatoshis == 50_000)
        #expect(!request.isDiagnosticsSafe)
        #expect(request.diagnosticsPrivacy == .private)

        #expect(
            throws: Host.MosaicHostContractError
                .invalidPreviousOutputHashLength(actual: 31)
        ) {
            _ = try Host.MosaicPreviousOutputRequest(
                transactionHashBytes: [UInt8](repeating: 0, count: 31),
                outputIndex: 0,
                expectedAmountSatoshis: 1
            )
        }
        #expect(
            throws: Host.MosaicHostContractError
                .zeroExpectedPreviousOutputAmount
        ) {
            _ = try Host.MosaicPreviousOutputRequest(
                transactionHashBytes: [UInt8](repeating: 0, count: 32),
                outputIndex: 0,
                expectedAmountSatoshis: 0
            )
        }
    }

    @Test(
        "Resolved output rejects malformed source data",
        arguments: ResolvedOutputSubstitution.allCases
    )
    func rejectMalformedResolvedOutput(
        _ substitution: ResolvedOutputSubstitution
    ) throws {
        var transactionHash = [UInt8](repeating: 0x31, count: 32)
        var amount: UInt64 = 50_000
        var lockingScript = MosaicUnsignedTransactionTranscriptFixtures
            .p2pkhLockingScript(fill: 0x66)
        let expectedFailure: Host.MosaicHostContractError
        switch substitution {
        case .transactionHashLength:
            transactionHash.removeLast()
            expectedFailure = .invalidPreviousOutputHashLength(actual: 31)
        case .amount:
            amount = 0
            expectedFailure = .zeroResolvedPreviousOutputAmount
        case .lockingScript:
            lockingScript = []
            expectedFailure = .emptyResolvedPreviousOutputLockingScript
        }
        #expect(throws: expectedFailure) {
            _ = try Host.MosaicPreviousOutput(
                transactionHashBytes: transactionHash,
                outputIndex: 4,
                amountSatoshis: amount,
                lockingScriptBytes: lockingScript,
                tokenState: .absent
            )
        }
    }

    @Test("Resolved output remains diagnostics-private and preserves token state")
    func preserveResolvedOutputTokenState() throws {
        let request = try makeRequest()
        let output = try Host.MosaicPreviousOutput(
            transactionHashBytes: request.transactionHashBytes,
            outputIndex: request.outputIndex,
            amountSatoshis: request.expectedAmountSatoshis,
            lockingScriptBytes:
                MosaicUnsignedTransactionTranscriptFixtures
                    .p2pkhLockingScript(fill: 0x66),
            tokenState: .present
        )
        #expect(output.tokenState == .present)
        #expect(!output.isDiagnosticsSafe)
        #expect(output.diagnosticsPrivacy == .private)
    }

    @Test("Mainnet transcript resolves one exact ordered request vector")
    func resolveMainnetTranscript() async throws {
        let transcript = try makeTranscript(profile: .opalMainnetAlpha)
        let source = SourceProbe()
        let validation = try await Alpha.PreviousOutputResolver(
            source: source
        ).resolve(for: transcript)

        #expect(validation.transcriptRoot == transcript.transcriptRoot)
        #expect(validation.spentInputs.count == 1)
        #expect(await source.receivedRequests.count == 1)
        let received = await source.receivedRequests[0]
        #expect(
            received[0].transactionHashBytes
                == transcript.transaction.inputs[0]
                    .previousTransactionHashLittleEndian.reversed()
        )
    }

    @Test("Resolver preserves outpoint ordering and attached amounts")
    func preserveMultiInputOrdering() async throws {
        let transcript = try makeMultiInputTranscript()
        let source = SourceProbe()
        let validation = try await Alpha.PreviousOutputResolver(
            source: source
        ).resolve(for: transcript)
        let received = try #require(await source.receivedRequests.first)

        #expect(received.map(\.transactionHashBytes.first) == [0x01, 0x80, 0xF0])
        #expect(received.map(\.expectedAmountSatoshis) == [20_000, 30_000, 10_000])
        #expect(validation.spentInputs.map(\.amountSatoshis) == [20_000, 30_000, 10_000])
        #expect(
            validation.spentInputs.map(\.outpointTransactionHashBytes)
                == received.map(\.transactionHashBytes)
        )
    }

    @Test("Resolver sanitizes source failure")
    func rejectSourceFailure() async throws {
        let transcript = try makeTranscript(profile: .opalMainnetAlpha)
        await #expect(throws: Alpha.PreviousOutputResolver.Failure.sourceRejected) {
            _ = try await Alpha.PreviousOutputResolver(
                source: SourceProbe(mode: .reject)
            ).resolve(for: transcript)
        }
    }

    @Test(
        "Resolver rejects every substituted output binding",
        arguments: BindingSubstitution.allCases
    )
    func rejectOutputSubstitution(
        _ substitution: BindingSubstitution
    ) async throws {
        let transcript: OpalFusion.Mosaic.OpalV0
            .UnsignedTransactionTranscript
        let mode: SourceProbe.Mode
        switch substitution {
        case .transactionHash:
            transcript = try makeTranscript(profile: .opalMainnetAlpha)
            mode = .substitutedHash
        case .outputIndex:
            transcript = try makeTranscript(profile: .opalMainnetAlpha)
            mode = .substitutedIndex
        case .amount:
            transcript = try makeTranscript(profile: .opalMainnetAlpha)
            mode = .substitutedAmount
        case .order:
            transcript = try makeMultiInputTranscript()
            mode = .reversed
        }
        await #expect(
            throws: Alpha.PreviousOutputResolver.Failure
                .outputMismatch(index: 0)
        ) {
            _ = try await Alpha.PreviousOutputResolver(
                source: SourceProbe(mode: mode)
            ).resolve(for: transcript)
        }
    }

    @Test("Resolver rejects token-bearing and wrong-count source results")
    func rejectTokenAndCountMismatch() async throws {
        let transcript = try makeTranscript(profile: .opalMainnetAlpha)
        await #expect(
            throws: Alpha.PreviousOutputResolver.Failure
                .tokenBearingOutput(index: 0)
        ) {
            _ = try await Alpha.PreviousOutputResolver(
                source: SourceProbe(mode: .tokenBearing)
            ).resolve(for: transcript)
        }
        await #expect(
            throws: Alpha.PreviousOutputResolver.Failure
                .outputCountMismatch(expected: 1, actual: 0)
        ) {
            _ = try await Alpha.PreviousOutputResolver(
                source: SourceProbe(mode: .wrongCount)
            ).resolve(for: transcript)
        }
    }

    @Test(
        "Resolver preserves cancellation after source I/O",
        .timeLimit(.minutes(1))
    )
    func preserveCancellation() async throws {
        let transcript = try makeTranscript(profile: .opalMainnetAlpha)
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let source = SourceProbe(suspension: suspension)
        let task = Task {
            try await Alpha.PreviousOutputResolver(source: source)
                .resolve(for: transcript)
        }
        await suspension.waitUntilSuspended()
        task.cancel()
        await suspension.resume()
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await source.receivedRequests.count == 1)
    }

    @Test(
        "Resolver preserves cancellation when the source returns another error",
        .timeLimit(.minutes(1))
    )
    func preserveCancellationOverSourceFailure() async throws {
        let transcript = try makeTranscript(profile: .opalMainnetAlpha)
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let source = SourceProbe(mode: .reject, suspension: suspension)
        let task = Task {
            try await Alpha.PreviousOutputResolver(source: source)
                .resolve(for: transcript)
        }
        await suspension.waitUntilSuspended()
        task.cancel()
        await suspension.resume()
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await source.receivedRequests.count == 1)
    }

    @Test(
        "Resolver does not start source I/O when already cancelled",
        .timeLimit(.minutes(1))
    )
    func rejectPreCancelledTask() async throws {
        let transcript = try makeTranscript(profile: .opalMainnetAlpha)
        let gate = MosaicRuntimeCoordinatorSuspensionProbe()
        await gate.arm()
        let source = SourceProbe()
        let task = Task {
            await gate.suspendIfArmed()
            return try await Alpha.PreviousOutputResolver(source: source)
                .resolve(for: transcript)
        }
        await gate.waitUntilSuspended()
        task.cancel()
        await gate.resume()
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await source.receivedRequests.isEmpty)
    }

    @Test("Resolver preserves source cancellation")
    func preserveSourceCancellation() async throws {
        let transcript = try makeTranscript(profile: .opalMainnetAlpha)
        let source = SourceProbe(mode: .cancel)
        await #expect(throws: CancellationError.self) {
            _ = try await Alpha.PreviousOutputResolver(source: source)
                .resolve(for: transcript)
        }
        #expect(await source.receivedRequests.count == 1)
    }

    @Test("Resolver remains mainnet-profile scoped")
    func rejectChipnetTranscript() async throws {
        let transcript = try makeTranscript(profile: .opalV0)
        let source = SourceProbe()
        await #expect(
            throws: Alpha.PreviousOutputResolver.Failure
                .unsupportedProfile(.opalV0)
        ) {
            _ = try await Alpha.PreviousOutputResolver(source: source)
                .resolve(for: transcript)
        }
        #expect(await source.receivedRequests.isEmpty)
    }

    private func makeRequest() throws -> Host.MosaicPreviousOutputRequest {
        try .init(
            transactionHashBytes: [UInt8](repeating: 0x31, count: 32),
            outputIndex: 4,
            expectedAmountSatoshis: 50_000
        )
    }

    private func makeTranscript(
        profile: OpalFusion.Mosaic.Profile
    ) throws -> OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript {
        let admission = try MosaicMainnetAlphaAdmissionLedgerFixtures
            .makeHarness(localRole: .contributor)
        return try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: admission.election.result.roster,
            manifest: admission.manifest.binding,
            profile: profile
        ).transcript
    }

    private func makeMultiInputTranscript() throws
        -> OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript {
        typealias OpalV0 = OpalFusion.Mosaic.OpalV0
        let admission = try MosaicMainnetAlphaAdmissionLedgerFixtures
            .makeHarness(localRole: .contributor)
        let roster = admission.election.result.roster
        let commitmentSet = try MosaicUnsignedTransactionTranscriptFixtures
            .makeCommitmentSet(
                contributorCount: roster.contributors.count,
                profile: .opalMainnetAlpha
            )
        let commitmentValidation = try OpalFusion.Mosaic.Attempt
            .CommitmentSetValidation(
                profile: .opalMainnetAlpha,
                roster: roster,
                commitmentSet: commitmentSet
            )
        let memberCount = roster.contributors.count
            * OpalV0.componentAuthorizationCountPerContributor
        let hashes: [(UInt8, UInt64)] = [
            (0xF0, 10_000),
            (0x01, 20_000),
            (0x80, 30_000),
        ]
        var components = try hashes.enumerated().map { index, entry in
            try OpalV0.Component(
                saltCommitment:
                    MosaicUnsignedTransactionTranscriptFixtures
                        .indexedDigest(50_000 + index),
                payload: .input(
                    try .init(
                        previousTransactionHash: [UInt8](
                            repeating: entry.0,
                            count: 32
                        ),
                        outputIndex: UInt32(index),
                        amountSatoshis: entry.1
                    )
                )
            )
        }
        components.append(
            try .init(
                saltCommitment:
                    MosaicUnsignedTransactionTranscriptFixtures
                        .indexedDigest(50_003),
                payload: .output(
                    try .init(
                        lockingScript:
                            MosaicUnsignedTransactionTranscriptFixtures
                                .p2pkhLockingScript(fill: 0x66),
                        amountSatoshis: 59_533
                    )
                )
            )
        )
        components.append(
            contentsOf: try (components.count ..< memberCount).map { index in
                try OpalV0.Component(
                    saltCommitment:
                        MosaicUnsignedTransactionTranscriptFixtures
                            .indexedDigest(50_000 + index),
                    payload: .blank
                )
            }
        )
        return try .init(
            profile: .opalMainnetAlpha,
            roster: roster,
            manifest: admission.manifest.binding,
            commitmentSet: commitmentValidation,
            componentSet: try .init(
                profile: .opalMainnetAlpha,
                components: components
            )
        )
    }
}
