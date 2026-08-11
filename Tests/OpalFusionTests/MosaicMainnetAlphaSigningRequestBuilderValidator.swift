// MosaicMainnetAlphaSigningRequestBuilderValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha signing-request builder")
struct MosaicMainnetAlphaSigningRequestBuilderValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Builder = Alpha.SigningRequestBuilder
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias Host = OpalFusion.Host
    typealias Session = Alpha.RuntimeSession

    private struct AcceptPublication:
        Session.ReservationPublicationValidating
    {
        func validateReservationPublication(
            _: Session.ReservationPublicationRequest
        ) throws {}
    }

    private struct PreviousOutputSource: Host.MosaicPreviousOutputSource {
        struct Outpoint: Hashable, Sendable {
            let transactionHash: [UInt8]
            let outputIndex: UInt32
        }

        enum SourceError: Error {
            case missingOutput
        }

        let lockingScripts: [Outpoint: [UInt8]]

        func resolvePreviousOutputs(
            for requests: [Host.MosaicPreviousOutputRequest]
        ) async throws -> [Host.MosaicPreviousOutput] {
            try requests.map { request in
                let outpoint = Outpoint(
                    transactionHash: request.transactionHashBytes,
                    outputIndex: request.outputIndex
                )
                guard let lockingScript = lockingScripts[outpoint] else {
                    throw SourceError.missingOutput
                }
                return try .init(
                    transactionHashBytes: request.transactionHashBytes,
                    outputIndex: request.outputIndex,
                    amountSatoshis: request.expectedAmountSatoshis,
                    lockingScriptBytes: lockingScript,
                    tokenState: .absent
                )
            }
        }
    }

    private struct Harness {
        let admission: Fixture.Harness
        let context: Session.Context
        let transcript: OpalFusion.Mosaic.OpalV0
            .UnsignedTransactionTranscript
        let publication: Session.ReservationPublicationValidation
        let transcriptInclusion: OpalFusion.Mosaic.LocalAttempt
            .TranscriptInclusionValidation
        let acknowledgementSet: Alpha.PreSignAcknowledgementSet
        let lease: Host.MosaicReservationLease
        let previousOutputs: Alpha.PreviousOutputResolver.Validation
        let publicKey: [UInt8]
    }

    enum LocalInputSubstitution: CaseIterable, Sendable {
        case duplicate
        case outpoint
        case amount
        case lockingScript
        case missingPublicKey
        case invalidP2PKH
        case invalidCurvePublicKey
    }

    @Test("Build the exact transcript-ordered host signing request")
    func buildExactRequest() async throws {
        let harness = try await makeHarness()
        let request = try build(harness)
        let expectedExcessFee = try Alpha.ContributionFeePolicy
            .requiredExcessFeeSatoshis(
                for: harness.context.localControlIdentity,
                in: harness.context.roster
            )

        #expect(request.reservationReference == harness.lease.reference)
        #expect(
            request.roundIdentifier
                == harness.admission.manifest.core.roundIdentifier
        )
        #expect(request.transcriptBinding == harness.transcript.transcriptBinding)
        #expect(
            request.unsignedTransactionBytes
                == harness.transcript.unsignedTransactionBytes
        )
        #expect(request.localInputIndices == [0])
        #expect(request.spentInputs.count == 1)
        #expect(request.spentInputs[0].publicKey == harness.publicKey)
        #expect(
            request.expectedLocalOutputs
                == harness.lease.participantReservation.outputs
        )
        #expect(
            request.requiredExcessFeeSatoshis
                == expectedExcessFee
        )
        #expect(
            request.transactionProfileIdentifier
                == OpalFusion.Mosaic.Profile.opalMainnetAlpha
                    .transactionProfileIdentifier
        )
    }

    @Test("Map reverse lease input order onto canonical transcript indices")
    func mapMultipleLocalInputs() async throws {
        let prepared = try await makeMultiInputHarness()
        let request = try build(prepared.harness)

        #expect(request.localInputIndices == [0, 2])
        #expect(
            request.spentInputs.map {
                $0.outpointTransactionHashBytes.first
            } == [0x10, 0x80, 0xF0]
        )
        #expect(
            request.spentInputs.map(\.publicKey) == [
                prepared.localPublicKeys[0],
                nil,
                prepared.localPublicKeys[2],
            ]
        )
        #expect(
            prepared.harness.lease.participantReservation.inputs.map {
                $0.outpointTransactionHashBytes.first
            } == [0xF0, 0x10]
        )
    }

    @Test("Reject unsupported profile and conductor signing")
    func rejectUnsupportedAuthority() async throws {
        let harness = try await makeHarness()
        let chipnetTranscript = try MosaicUnsignedTransactionTranscriptFixtures
            .prepare(
                roster: harness.context.roster,
                manifest: harness.admission.manifest.binding,
                profile: .opalV0
            ).transcript
        let chipnetInclusion = try makeTranscriptInclusion(
            harness: harness,
            transcript: chipnetTranscript
        )
        #expect(throws: Builder.Failure.unsupportedProfile(.opalV0)) {
            _ = try build(
                harness,
                transcriptInclusion: chipnetInclusion
            )
        }

        let conductorContext = Session.Context(
            attemptIdentifier: harness.context.attemptIdentifier,
            generationIdentifier: harness.context.generationIdentifier,
            materialIdentifier: harness.context.materialIdentifier,
            localControlIdentity: harness.context.roster.conductor,
            localRole: .conductor,
            roster: harness.context.roster,
            proposalRoundIdentifier: harness.context.proposalRoundIdentifier
        )
        #expect(throws: Builder.Failure.localPeerIsNotContributor) {
            _ = try build(harness, context: conductorContext)
        }
    }

    @Test("Reject context, reservation-publication, and manifest substitution")
    func rejectRuntimeBindingSubstitution() async throws {
        let harness = try await makeHarness()
        let foreignContext = Session.Context(
            attemptIdentifier: harness.context.attemptIdentifier,
            generationIdentifier: harness.context.generationIdentifier,
            materialIdentifier: .init(
                opaqueBytes: [UInt8](repeating: 0xFF, count: 32)
            ),
            localControlIdentity: harness.context.localControlIdentity,
            localRole: harness.context.localRole,
            roster: harness.context.roster,
            proposalRoundIdentifier: harness.context.proposalRoundIdentifier
        )
        #expect(throws: Builder.Failure.contextBindingMismatch) {
            _ = try build(harness, context: foreignContext)
        }

        let foreignMaterialInclusion = try makeTranscriptInclusion(
            context: foreignContext,
            transcript: harness.transcript
        )
        #expect(throws: Builder.Failure.transcriptInclusionMismatch) {
            _ = try build(
                harness,
                transcriptInclusion: foreignMaterialInclusion
            )
        }

        let foreignPlayerCommit = try #require(
            Fixture.makePlayerCommits(
                harness: harness.admission,
                commitmentSet: harness.transcript.commitmentSet
            ).first { $0.contributor != harness.context.localControlIdentity }
        )
        let foreignPublication = try makePublication(
            harness: harness,
            lease: harness.lease,
            playerCommit: foreignPlayerCommit
        )
        #expect(throws: Builder.Failure.reservationPublicationMismatch) {
            _ = try build(harness, publication: foreignPublication)
        }

        let foreignBinding = try Attempt.ManifestBinding(
            validatedRoundIdentifier:
                harness.admission.manifest.core.roundIdentifier,
            validatedManifestDigest: [UInt8](repeating: 0xFF, count: 32)
        )
        let foreignTranscript = try MosaicUnsignedTransactionTranscriptFixtures
            .prepare(
                roster: harness.context.roster,
                manifest: foreignBinding,
                profile: .opalMainnetAlpha
            ).transcript
        let foreignManifestInclusion = try makeTranscriptInclusion(
            harness: harness,
            transcript: foreignTranscript
        )
        #expect(throws: Builder.Failure.manifestMismatch) {
            _ = try build(
                harness,
                transcriptInclusion: foreignManifestInclusion
            )
        }

        let foreignAcknowledgementSet = try makeAcknowledgementSet(
            admission: harness.admission,
            transcript: foreignTranscript
        )
        #expect(throws: Builder.Failure.acknowledgementSetMismatch) {
            _ = try build(
                harness,
                acknowledgementSet: foreignAcknowledgementSet
            )
        }

        let foreignRoundBinding = try Attempt.ManifestBinding(
            validatedRoundIdentifier: [UInt8](repeating: 0xFE, count: 32),
            validatedManifestDigest:
                harness.admission.manifest.binding.manifestDigest
        )
        let foreignRoundAcknowledgementSet = try makeAcknowledgementSet(
            admission: harness.admission,
            transcript: harness.transcript,
            binding: foreignRoundBinding
        )
        #expect(throws: Builder.Failure.acknowledgementSetMismatch) {
            _ = try build(
                harness,
                acknowledgementSet: foreignRoundAcknowledgementSet
            )
        }

        var substitutedContributors = harness.context.roster.contributors
        substitutedContributors[0] = MosaicManifestSignatureFixtures
            .controlIdentity(scalarByte: 8)
        let substitutedRoster = try Attempt.Roster(
            members: [
                .init(
                    controlIdentity: harness.context.roster.conductor,
                    role: .conductor
                ),
            ] + substitutedContributors.map {
                .init(controlIdentity: $0, role: .contributor)
            }
        )
        let substitutedRosterAcknowledgementSet = try makeAcknowledgementSet(
            admission: harness.admission,
            transcript: harness.transcript,
            roster: substitutedRoster
        )
        #expect(throws: Builder.Failure.acknowledgementSetMismatch) {
            _ = try build(
                harness,
                acknowledgementSet: substitutedRosterAcknowledgementSet
            )
        }
    }

    @Test("Reject substituted previous-output validation")
    func rejectPreviousOutputSubstitution() async throws {
        let harness = try await makeHarness()
        let foreignTranscript = try MosaicUnsignedTransactionTranscriptFixtures
            .prepare(
                roster: harness.context.roster,
                manifest: harness.admission.manifest.binding,
                profile: .opalMainnetAlpha,
                componentSaltOffset: 10_000
            ).transcript
        let foreignValidation = try await resolvePreviousOutputs(
            for: foreignTranscript,
            reservedInputs: harness.lease.participantReservation.inputs
        )
        #expect(throws: Builder.Failure.previousOutputTranscriptMismatch) {
            _ = try build(harness, previousOutputs: foreignValidation)
        }
    }

    @Test(
        "Reject every local-input substitution",
        arguments: LocalInputSubstitution.allCases
    )
    func rejectLocalInputSubstitution(
        _ substitution: LocalInputSubstitution
    ) async throws {
        let harness = try await makeHarness()
        let original = harness.lease.participantReservation.inputs[0]
        var inputs = [original]
        var previousOutputs = harness.previousOutputs
        let expectedFailure: Builder.Failure

        switch substitution {
        case .duplicate:
            inputs.append(original)
            expectedFailure = .duplicateLocalInput(index: 1)
        case .outpoint:
            var hash = original.outpointTransactionHashBytes
            hash[0] ^= 0x01
            inputs[0] = participantInput(
                from: original,
                transactionHash: hash
            )
            expectedFailure = .localInputMissing(index: 0)
        case .amount:
            inputs[0] = participantInput(
                from: original,
                amountSatoshis: original.amountSatoshis + 1
            )
            expectedFailure = .localInputAmountMismatch(index: 0)
        case .lockingScript:
            inputs[0] = participantInput(
                from: original,
                lockingScript: [0x51]
            )
            expectedFailure = .localInputLockingScriptMismatch(index: 0)
        case .missingPublicKey:
            inputs[0] = participantInput(
                from: original,
                removingPublicKey: true
            )
            expectedFailure = .localInputPublicKeyMissing(index: 0)
        case .invalidP2PKH:
            inputs[0] = participantInput(
                from: original,
                lockingScript: [0x51]
            )
            previousOutputs = try await resolvePreviousOutputs(
                for: harness.transcript,
                reservedInputs: inputs
            )
            expectedFailure = .invalidLocalP2PKHLockingScript(index: 0)
        case .invalidCurvePublicKey:
            let invalidPublicKey = [UInt8(0x02)]
                + [UInt8](repeating: 0xFF, count: 32)
            let matchingScript = [UInt8(0x76), 0xA9, 0x14]
                + OpalFusion.Execution.ProtocolPrimitives.hash160(
                    invalidPublicKey
                )
                + [0x88, 0xAC]
            inputs[0] = participantInput(
                from: original,
                lockingScript: matchingScript,
                publicKey: invalidPublicKey
            )
            previousOutputs = try await resolvePreviousOutputs(
                for: harness.transcript,
                reservedInputs: inputs
            )
            expectedFailure = .invalidLocalP2PKHLockingScript(index: 0)
        }

        let lease = try makeLease(
            reference: harness.lease.reference,
            inputs: inputs,
            outputs: harness.lease.participantReservation.outputs
        )
        #expect(throws: expectedFailure) {
            _ = try build(
                harness,
                publication: try makePublication(
                    harness: harness,
                    lease: lease
                ),
                previousOutputs: previousOutputs
            )
        }
    }

    @Test("Reject a reserved output absent from the transcript")
    func rejectLocalOutputSubstitution() async throws {
        let harness = try await makeHarness()
        let original = harness.lease.participantReservation.outputs[0]
        let lease = try makeLease(
            reference: harness.lease.reference,
            inputs: harness.lease.participantReservation.inputs,
            outputs: [
                .init(
                    lockingScriptBytes: original.lockingScriptBytes,
                    amountSatoshis: original.amountSatoshis + 1
                ),
            ]
        )
        #expect(throws: Builder.Failure.localOutputMissing(index: 0)) {
            _ = try build(
                harness,
                publication: try makePublication(
                    harness: harness,
                    lease: lease
                )
            )
        }

        let duplicateLease = try makeLease(
            reference: harness.lease.reference,
            inputs: harness.lease.participantReservation.inputs,
            outputs: [original, original]
        )
        #expect(throws: Builder.Failure.localOutputMissing(index: 1)) {
            _ = try build(
                harness,
                publication: try makePublication(
                    harness: harness,
                    lease: duplicateLease
                )
            )
        }
    }

    private func makeHarness() async throws -> Harness {
        let admission = try Fixture.makeHarness(localRole: .contributor)
        let materialIdentifier = Session.MaterialIdentifier(
            opaqueBytes: [UInt8](repeating: 0xA3, count: 32)
        )
        let context = Session.Context(
            attemptIdentifier: admission.attemptIdentifier,
            generationIdentifier: admission.generationIdentifier,
            materialIdentifier: materialIdentifier,
            localControlIdentity: admission.localControlIdentity,
            localRole: .contributor,
            roster: admission.election.result.roster,
            proposalRoundIdentifier: admission.manifest.core.roundIdentifier
        )
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures
            .prepare(
                roster: context.roster,
                manifest: admission.manifest.binding,
                profile: .opalMainnetAlpha
            )
        let transcript = preparation.transcript
        let input = try #require(
            transcript.componentSet.components.compactMap {
                component -> OpalFusion.Mosaic.OpalV0.InputComponent? in
                guard case let .input(input) = component.payload else {
                    return nil
                }
                return input
            }.first
        )
        let output = try #require(transcript.transaction.outputs.first)
        let signingKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([0x01])
        )
        let publicKey = [UInt8](signingKey.publicKey.compressedRepresentation)
        let lockingScript = [UInt8(0x76), 0xA9, 0x14]
            + OpalFusion.Execution.ProtocolPrimitives.hash160(publicKey)
            + [0x88, 0xAC]
        let reference = reservationReference()
        let lease = try makeLease(
            reference: reference,
            inputs: [
                .init(
                    outpointTransactionHashBytes:
                        input.previousTransactionHash,
                    outpointIndex: input.outputIndex,
                    amountSatoshis: input.amountSatoshis,
                    lockingScriptBytes: lockingScript,
                    publicKey: publicKey
                ),
            ],
            outputs: [
                .init(
                    lockingScriptBytes: output.lockingScript,
                    amountSatoshis: output.amountSatoshis
                ),
            ]
        )
        let playerCommit = try #require(
            Fixture.makePlayerCommits(
                harness: admission,
                commitmentSet: preparation.commitmentSet
            ).first { $0.contributor == admission.localControlIdentity }
        )
        let publicationRequest = Session.ReservationPublicationRequest(
            attemptIdentifier: context.attemptIdentifier,
            generationIdentifier: context.generationIdentifier,
            materialIdentifier: context.materialIdentifier,
            contributor: context.localControlIdentity,
            manifest: admission.manifest,
            reservationLease: lease,
            playerCommit: playerCommit
        )
        let publication = try Session.ReservationPublicationValidation(
            validating: publicationRequest,
            using: AcceptPublication()
        )
        let transcriptInclusion = try makeTranscriptInclusion(
            context: context,
            transcript: transcript
        )
        let acknowledgementSet = try makeAcknowledgementSet(
            admission: admission,
            transcript: transcript
        )
        let previousOutputs = try await resolvePreviousOutputs(
            for: transcript,
            reservedInputs: lease.participantReservation.inputs
        )
        return .init(
            admission: admission,
            context: context,
            transcript: transcript,
            publication: publication,
            transcriptInclusion: transcriptInclusion,
            acknowledgementSet: acknowledgementSet,
            lease: lease,
            previousOutputs: previousOutputs,
            publicKey: publicKey
        )
    }

    private func makeMultiInputHarness() async throws -> (
        harness: Harness,
        localPublicKeys: [Int: [UInt8]]
    ) {
        typealias OpalV0 = OpalFusion.Mosaic.OpalV0
        let admission = try Fixture.makeHarness(localRole: .contributor)
        let materialIdentifier = Session.MaterialIdentifier(
            opaqueBytes: [UInt8](repeating: 0xA3, count: 32)
        )
        let context = Session.Context(
            attemptIdentifier: admission.attemptIdentifier,
            generationIdentifier: admission.generationIdentifier,
            materialIdentifier: materialIdentifier,
            localControlIdentity: admission.localControlIdentity,
            localRole: .contributor,
            roster: admission.election.result.roster,
            proposalRoundIdentifier: admission.manifest.core.roundIdentifier
        )
        let commitmentSet = try MosaicUnsignedTransactionTranscriptFixtures
            .makeCommitmentSet(
                contributorCount: context.roster.contributors.count,
                profile: .opalMainnetAlpha
            )
        let commitmentValidation = try Attempt.CommitmentSetValidation(
            profile: .opalMainnetAlpha,
            roster: context.roster,
            commitmentSet: commitmentSet
        )
        let memberCount = context.roster.contributors.count
            * OpalV0.componentAuthorizationCountPerContributor
        let inputValues: [(UInt8, UInt64)] = [
            (0xF0, 40_000),
            (0x10, 20_000),
            (0x80, 30_000),
        ]
        var components = try inputValues.enumerated().map { index, value in
            try OpalV0.Component(
                saltCommitment:
                    MosaicUnsignedTransactionTranscriptFixtures
                        .indexedDigest(60_000 + index),
                payload: .input(
                    try .init(
                        previousTransactionHash: [UInt8](
                            repeating: value.0,
                            count: 32
                        ),
                        outputIndex: UInt32(index),
                        amountSatoshis: value.1
                    )
                )
            )
        }
        components.append(
            try .init(
                saltCommitment:
                    MosaicUnsignedTransactionTranscriptFixtures
                        .indexedDigest(60_003),
                payload: .output(
                    try .init(
                        lockingScript:
                            MosaicUnsignedTransactionTranscriptFixtures
                                .p2pkhLockingScript(fill: 0x77),
                        amountSatoshis: 89_533
                    )
                )
            )
        )
        components.append(
            contentsOf: try (4 ..< memberCount).map { index in
                try OpalV0.Component(
                    saltCommitment:
                        MosaicUnsignedTransactionTranscriptFixtures
                            .indexedDigest(60_000 + index),
                    payload: .blank
                )
            }
        )
        let componentSet = try OpalV0.ComponentSet(
            profile: .opalMainnetAlpha,
            components: components
        )
        let transcript = try OpalV0.UnsignedTransactionTranscript(
            profile: .opalMainnetAlpha,
            roster: context.roster,
            manifest: admission.manifest.binding,
            commitmentSet: commitmentValidation,
            componentSet: componentSet
        )
        let committedInputs = transcript.componentSet.components.compactMap {
            component -> OpalV0.InputComponent? in
            guard case let .input(input) = component.payload else {
                return nil
            }
            return input
        }.sorted { lhs, rhs in
            if lhs.previousTransactionHash != rhs.previousTransactionHash {
                return lhs.previousTransactionHash.lexicographicallyPrecedes(
                    rhs.previousTransactionHash
                )
            }
            return lhs.outputIndex < rhs.outputIndex
        }
        var authoritativeInputs: [Host.ParticipantInput] = []
        var authoritativePublicKeys: [[UInt8]] = []
        for (index, input) in committedInputs.enumerated() {
            let signingKey = try OpalCrypto.Secp256k1.SigningKey(
                rawRepresentation: Data(repeating: 0, count: 31)
                    + Data([UInt8(index + 1)])
            )
            let publicKey = [UInt8](
                signingKey.publicKey.compressedRepresentation
            )
            let lockingScript = [UInt8(0x76), 0xA9, 0x14]
                + OpalFusion.Execution.ProtocolPrimitives.hash160(publicKey)
                + [0x88, 0xAC]
            authoritativeInputs.append(.init(
                outpointTransactionHashBytes: input.previousTransactionHash,
                outpointIndex: input.outputIndex,
                amountSatoshis: input.amountSatoshis,
                lockingScriptBytes: lockingScript,
                publicKey: publicKey
            ))
            authoritativePublicKeys.append(publicKey)
        }
        let localIndices = [2, 0]
        let localInputs = localIndices.map { authoritativeInputs[$0] }
        let localPublicKeys = Dictionary(
            uniqueKeysWithValues: localIndices.map {
                ($0, authoritativePublicKeys[$0])
            }
        )
        let output = try #require(transcript.transaction.outputs.first)
        let lease = try makeLease(
            reference: reservationReference(finalByte: 0xD3),
            inputs: localInputs,
            outputs: [
                .init(
                    lockingScriptBytes: output.lockingScript,
                    amountSatoshis: output.amountSatoshis
                ),
            ]
        )
        let playerCommit = try #require(
            Fixture.makePlayerCommits(
                harness: admission,
                commitmentSet: commitmentSet
            ).first { $0.contributor == context.localControlIdentity }
        )
        let publicationRequest = Session.ReservationPublicationRequest(
            attemptIdentifier: context.attemptIdentifier,
            generationIdentifier: context.generationIdentifier,
            materialIdentifier: context.materialIdentifier,
            contributor: context.localControlIdentity,
            manifest: admission.manifest,
            reservationLease: lease,
            playerCommit: playerCommit
        )
        let publication = try Session.ReservationPublicationValidation(
            validating: publicationRequest,
            using: AcceptPublication()
        )
        let inclusion = try makeTranscriptInclusion(
            context: context,
            transcript: transcript
        )
        let acknowledgementSet = try makeAcknowledgementSet(
            admission: admission,
            transcript: transcript
        )
        let previousOutputs = try await resolvePreviousOutputs(
            for: transcript,
            reservedInputs: authoritativeInputs
        )
        return (
            .init(
                admission: admission,
                context: context,
                transcript: transcript,
                publication: publication,
                transcriptInclusion: inclusion,
                acknowledgementSet: acknowledgementSet,
                lease: lease,
                previousOutputs: previousOutputs,
                publicKey: try #require(localPublicKeys[0])
            ),
            localPublicKeys
        )
    }

    private func build(
        _ harness: Harness,
        context: Session.Context? = nil,
        publication: Session.ReservationPublicationValidation? = nil,
        transcriptInclusion: OpalFusion.Mosaic.LocalAttempt
            .TranscriptInclusionValidation? = nil,
        acknowledgementSet: Alpha.PreSignAcknowledgementSet? = nil,
        previousOutputs: Alpha.PreviousOutputResolver.Validation? = nil
    ) throws -> Host.MosaicTransactionSigningRequest {
        try Builder.build(
            context: context ?? harness.context,
            reservationPublication: publication ?? harness.publication,
            transcriptInclusion:
                transcriptInclusion ?? harness.transcriptInclusion,
            acknowledgementSet:
                acknowledgementSet ?? harness.acknowledgementSet,
            previousOutputs: previousOutputs ?? harness.previousOutputs
        )
    }

    private func makePublication(
        harness: Harness,
        lease: Host.MosaicReservationLease,
        playerCommit: Alpha.PlayerCommit? = nil
    ) throws -> Session.ReservationPublicationValidation {
        let request = Session.ReservationPublicationRequest(
            attemptIdentifier: harness.context.attemptIdentifier,
            generationIdentifier: harness.context.generationIdentifier,
            materialIdentifier: harness.context.materialIdentifier,
            contributor: harness.context.localControlIdentity,
            manifest: harness.admission.manifest,
            reservationLease: lease,
            playerCommit:
                playerCommit ?? harness.publication.request.playerCommit
        )
        return try .init(
            validating: request,
            using: AcceptPublication()
        )
    }

    private func makeTranscriptInclusion(
        harness: Harness,
        transcript: OpalFusion.Mosaic.OpalV0
            .UnsignedTransactionTranscript
    ) throws -> OpalFusion.Mosaic.LocalAttempt
        .TranscriptInclusionValidation {
        try makeTranscriptInclusion(
            context: harness.context,
            transcript: transcript
        )
    }

    private func makeTranscriptInclusion(
        context: Session.Context,
        transcript: OpalFusion.Mosaic.OpalV0
            .UnsignedTransactionTranscript
    ) throws -> OpalFusion.Mosaic.LocalAttempt
        .TranscriptInclusionValidation {
        try MosaicUnsignedTransactionTranscriptFixtures
            .makeTranscriptInclusionValidation(
                attemptIdentifier: context.attemptIdentifier,
                generationIdentifier: context.generationIdentifier,
                contributor: context.localControlIdentity,
                materialIdentifier: context.materialIdentifier,
                transcript: transcript
            )
    }

    private func makeAcknowledgementSet(
        admission: Fixture.Harness,
        transcript: OpalFusion.Mosaic.OpalV0
            .UnsignedTransactionTranscript,
        binding: Attempt.ManifestBinding? = nil,
        roster: Attempt.Roster? = nil
    ) throws -> Alpha.PreSignAcknowledgementSet {
        let binding = binding ?? admission.manifest.binding
        let roster = roster ?? admission.election.result.roster
        let acknowledgements = MosaicManifestSignatureFixtures
            .transcriptAcknowledgements(
                for: roster.contributors,
                binding: binding,
                transcriptRoot: transcript.transcriptRoot,
                profile: .opalMainnetAlpha
            )
        let submissions = try acknowledgements.sorted {
            $0.contributor.validatedBytes.lexicographicallyPrecedes(
                $1.contributor.validatedBytes
            )
        }.map {
            try Alpha.PreSignAcknowledgementSubmission(
                contributor: $0.contributor,
                roundIdentifier: $0.roundIdentifier,
                transcriptRoot: $0.transcriptRoot,
                signature: $0.rawRepresentation
            )
        }
        return try .init(
            roundIdentifier: binding.roundIdentifier,
            transcriptRoot: transcript.transcriptRoot.validatedBytes,
            roster: roster,
            submissions: submissions
        )
    }

    private func resolvePreviousOutputs(
        for transcript: OpalFusion.Mosaic.OpalV0
            .UnsignedTransactionTranscript,
        reservedInputs: [Host.ParticipantInput]
    ) async throws -> Alpha.PreviousOutputResolver.Validation {
        let lockingScripts = Dictionary(
            uniqueKeysWithValues: reservedInputs.map {
                (
                    PreviousOutputSource.Outpoint(
                        transactionHash: $0.outpointTransactionHashBytes,
                        outputIndex: $0.outpointIndex
                    ),
                    $0.lockingScriptBytes
                )
            }
        )
        return try await Alpha.PreviousOutputResolver(
            source: PreviousOutputSource(lockingScripts: lockingScripts)
        ).resolve(for: transcript)
    }

    private func participantInput(
        from input: Host.ParticipantInput,
        transactionHash: [UInt8]? = nil,
        amountSatoshis: UInt64? = nil,
        lockingScript: [UInt8]? = nil,
        publicKey: [UInt8]? = nil,
        removingPublicKey: Bool = false
    ) -> Host.ParticipantInput {
        .init(
            outpointTransactionHashBytes:
                transactionHash ?? input.outpointTransactionHashBytes,
            outpointIndex: input.outpointIndex,
            amountSatoshis: amountSatoshis ?? input.amountSatoshis,
            lockingScriptBytes: lockingScript ?? input.lockingScriptBytes,
            publicKey: removingPublicKey ? nil : publicKey ?? input.publicKey
        )
    }

    private func makeLease(
        reference: Host.MosaicReservationReference,
        inputs: [Host.ParticipantInput],
        outputs: [Host.ParticipantOutput]
    ) throws -> Host.MosaicReservationLease {
        try .init(
            reference: reference,
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            participantReservation: .init(inputs: inputs, outputs: outputs)
        )
    }

    private func reservationReference(
        finalByte: UInt8 = 0xD1
    ) -> Host.MosaicReservationReference {
        .init(
            identifier: UUID(
                uuid: (
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, finalByte
                )
            ),
            generation: 1
        )
    }
}
