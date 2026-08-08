// MosaicUnsignedTransactionTranscriptValidator.swift

import Testing
@testable import OpalFusion

@Suite("Mosaic Opal-v0 unsigned transaction transcript")
struct MosaicUnsignedTransactionTranscriptValidator {
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias LocalAttempt = OpalFusion.Mosaic.LocalAttempt
    typealias OpalV0 = OpalFusion.Mosaic.OpalV0

    @Test("Pin exact unsigned transaction and transcript bytes")
    func pinExactTransactionAndTranscript() throws {
        let roster = try makeRoster(candidateCount: 7)
        let prepared = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: roster,
            manifest: manifest
        )
        let transaction = prepared.transcript.transaction

        #expect(
            hexadecimal(prepared.transcript.unsignedTransactionBytes)
                == "0200000001e8030000000000000000000000000000000000000000000000000000000000000300000000ffffffff0110270000000000001976a914666666666666666666666666666666666666666688ac00000000"
        )
        #expect(transaction.version == 2)
        #expect(transaction.lockTime == 0)
        #expect(transaction.inputs.count == 1)
        #expect(transaction.inputs[0].unlockingScript.isEmpty)
        #expect(transaction.inputs[0].sequence == UInt32.max)
        #expect(transaction.outputs.count == 1)
        #expect(transaction.outputs[0].lockingScript.first != 0x6A)
        #expect(prepared.transcript.estimatedFinalSignedByteCount == 185)
        #expect(prepared.transcript.feeSatoshis == 185)
        #expect(
            hexadecimal(
                prepared.transcript.transcriptBinding.unsignedTransactionDigest
            ) == "86c6755ef57c9b383682d5b49eeed239b4fe13226d2966345ae60bde64abeec2"
        )
        #expect(
            hexadecimal(prepared.commitmentSet.digest)
                == "3c0adbafb3a391fecf54a7bef2ebe0e683ff0b2e00525aa4a4c267c2f999f794"
        )
        #expect(
            hexadecimal(prepared.componentSet.digest)
                == "adb8ed7ec5db7013a2b6669aa2a816cd52b198c6ee6dd886a1f25ed40fdabc93"
        )
        #expect(
            hexadecimal(prepared.transcript.transcriptRoot.validatedBytes)
                == "183b5e093430bb70b72d3d3599e4cf541021432ac3b7fc3820fed798b15fe38a"
        )
    }

    @Test("Sort inputs and outputs independently of component order")
    func sortTransactionMembersDeterministically() throws {
        let roster = try makeRoster(candidateCount: 7)
        let componentSet = try makeOrderedComponentSet(
            contributorCount: roster.contributors.count
        )
        let reversedSet = try OpalV0.ComponentSet(
            components: Array(componentSet.components.reversed())
        )
        let first = try makeTranscript(roster: roster, componentSet: componentSet)
        let second = try makeTranscript(roster: roster, componentSet: reversedSet)

        #expect(first == second)
        #expect(
            first.transaction.inputs.map(\.previousOutputIndex) == [2, 9, 4]
        )
        #expect(
            first.transaction.inputs.map {
                Array($0.previousTransactionHashLittleEndian.reversed())
            } == [indexedDigest(4), indexedDigest(4), indexedDigest(5)]
        )
        #expect(first.transaction.outputs.map(\.amountSatoshis) == [2_500, 2_500])
        #expect(first.transaction.outputs[0].lockingScript == p2pkh(fill: 0x10))
        #expect(first.transaction.outputs[1].lockingScript == p2pkh(fill: 0x20))
    }

    @Test(
        "Accept every Opal-v0 contributor boundary",
        arguments: [7, 8, 9]
    )
    func acceptContributorBoundaries(candidateCount: Int) throws {
        let roster = try makeRoster(candidateCount: candidateCount)
        let prepared = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: roster,
            manifest: manifest
        )
        let expectedMemberCount = roster.contributors.count
            * OpalV0.componentAuthorizationCountPerContributor

        #expect(prepared.commitmentSet.commitments.count == expectedMemberCount)
        #expect(
            prepared.transcript.componentSet.components.count
                == expectedMemberCount
        )
        #expect(prepared.transcript.transaction.inputs.count == 1)
        #expect(prepared.transcript.transaction.outputs.count == 1)
    }

    @Test("Reject aggregate counts that do not match the elected roster")
    func rejectAggregateCountMismatches() throws {
        let roster = try makeRoster(candidateCount: 7)
        let sevenContributorCommitments = try MosaicUnsignedTransactionTranscriptFixtures
            .makeCommitmentSet(contributorCount: 7)
        #expect(
            throws: Attempt.CommitmentSetValidation.ValidationError
                .invalidMemberCount(expected: 138, actual: 161)
        ) {
            _ = try Attempt.CommitmentSetValidation(
                profile: .opalV0,
                roster: roster,
                commitmentSet: sevenContributorCommitments
            )
        }

        let commitmentSet = try MosaicUnsignedTransactionTranscriptFixtures
            .makeCommitmentSet(contributorCount: 6)
        let validation = try Attempt.CommitmentSetValidation(
            profile: .opalV0,
            roster: roster,
            commitmentSet: commitmentSet
        )
        let sevenContributorComponents = try MosaicUnsignedTransactionTranscriptFixtures
            .makeBalancedComponentSet(contributorCount: 7)
        #expect(
            throws: OpalV0.UnsignedTransactionTranscript.ValidationError
                .invalidComponentCount(expected: 138, actual: 161)
        ) {
            _ = try OpalV0.UnsignedTransactionTranscript(
                roster: roster,
                manifest: manifest,
                commitmentSet: validation,
                componentSet: sevenContributorComponents
            )
        }

        let eightCandidateRoster = try makeRoster(candidateCount: 8)
        let sevenContributorValidation = try Attempt.CommitmentSetValidation(
            profile: .opalV0,
            roster: eightCandidateRoster,
            commitmentSet: sevenContributorCommitments
        )
        let sixContributorComponents = try MosaicUnsignedTransactionTranscriptFixtures
            .makeBalancedComponentSet(contributorCount: 6)
        #expect(
            throws: OpalV0.UnsignedTransactionTranscript.ValidationError
                .contributorRosterMismatch
        ) {
            _ = try OpalV0.UnsignedTransactionTranscript(
                roster: roster,
                manifest: manifest,
                commitmentSet: sevenContributorValidation,
                componentSet: sixContributorComponents
            )
        }

        let sameCountDifferentRoster = try makeRoster(
            candidateCount: 7,
            identityOffset: 0x40
        )
        let differentRosterValidation = try Attempt.CommitmentSetValidation(
            profile: .opalV0,
            roster: sameCountDifferentRoster,
            commitmentSet: commitmentSet
        )
        #expect(
            throws: OpalV0.UnsignedTransactionTranscript.ValidationError
                .contributorRosterMismatch
        ) {
            _ = try OpalV0.UnsignedTransactionTranscript(
                roster: roster,
                manifest: manifest,
                commitmentSet: differentRosterValidation,
                componentSet: sixContributorComponents
            )
        }
    }

    @Test("Fail closed outside the Opal-v0 profile")
    func rejectUnsupportedProfile() throws {
        let roster = try makeRoster(candidateCount: 7)
        let commitmentSet = try MosaicUnsignedTransactionTranscriptFixtures
            .makeCommitmentSet(contributorCount: 6)
        #expect(
            throws: Attempt.CommitmentSetValidation.ValidationError
                .unsupportedProfile(.draft1)
        ) {
            _ = try Attempt.CommitmentSetValidation(
                profile: .draft1,
                roster: roster,
                commitmentSet: commitmentSet
            )
        }

    }

    @Test("Do not mint local inclusion validation when its validator rejects")
    func rejectFailedLocalInclusionValidation() throws {
        let roster = try makeRoster(candidateCount: 7)
        let prepared = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: roster,
            manifest: manifest
        )

        #expect(
            throws: LocalAttempt.TranscriptInclusionValidation.ValidationError
                .inclusionRejected
        ) {
            _ = try LocalAttempt.TranscriptInclusionValidation(
                attemptIdentifier: .init(validatedBytes: [0x11]),
                generationIdentifier: .init(opaqueBytes: [0x22]),
                contributor: roster.contributors[0],
                materialIdentifier: .init(opaqueBytes: [0x33]),
                transcript: prepared.transcript,
                using: RejectingTranscriptInclusionValidator()
            )
        }
    }

    @Test("Reject missing input and output transaction shapes")
    func rejectMissingTransactionMembers() throws {
        let roster = try makeRoster(candidateCount: 7)
        let commitmentValidation = try makeCommitmentValidation(roster: roster)
        let memberCount = roster.contributors.count
            * OpalV0.componentAuthorizationCountPerContributor

        let blankOnly = try OpalV0.ComponentSet(
            components: try (0 ..< memberCount).map { index in
                try .init(saltCommitment: indexedDigest(index), payload: .blank)
            }
        )
        #expect(
            throws: OpalV0.UnsignedTransactionTranscript.ValidationError.missingInput
        ) {
            _ = try makeTranscript(
                roster: roster,
                commitmentValidation: commitmentValidation,
                componentSet: blankOnly
            )
        }

        let inputOnly = try paddedComponentSet(
            contributorCount: roster.contributors.count,
            leading: [
                try .init(
                    saltCommitment: indexedDigest(0),
                    payload: .input(
                        try .init(
                            previousTransactionHash: indexedDigest(3),
                            outputIndex: 0,
                            amountSatoshis: 1_000
                        )
                    )
                )
            ]
        )
        #expect(
            throws: OpalV0.UnsignedTransactionTranscript.ValidationError.missingOutput
        ) {
            _ = try makeTranscript(
                roster: roster,
                commitmentValidation: commitmentValidation,
                componentSet: inputOnly
            )
        }

        let outputOnly = try paddedComponentSet(
            contributorCount: roster.contributors.count,
            leading: [
                try .init(
                    saltCommitment: indexedDigest(0),
                    payload: .output(
                        try .init(
                            lockingScript: p2pkh(fill: 0x11),
                            amountSatoshis: 1_000
                        )
                    )
                )
            ]
        )
        #expect(
            throws: OpalV0.UnsignedTransactionTranscript.ValidationError.missingInput
        ) {
            _ = try makeTranscript(
                roster: roster,
                commitmentValidation: commitmentValidation,
                componentSet: outputOnly
            )
        }
    }

    @Test("Require the exact one-satoshi-per-final-byte fee")
    func rejectFeeMismatches() throws {
        let roster = try makeRoster(candidateCount: 7)
        for inputAmount in [UInt64(10_184), 10_186] {
            let actualFee = inputAmount - 10_000
            let componentSet = try makeSingleInputOutputSet(
                contributorCount: roster.contributors.count,
                inputAmount: inputAmount,
                outputAmount: 10_000
            )
            #expect(
                throws: OpalV0.UnsignedTransactionTranscript.ValidationError
                    .feeMismatch(expected: 185, actual: actualFee)
            ) {
                _ = try makeTranscript(roster: roster, componentSet: componentSet)
            }
        }

        let overspent = try makeSingleInputOutputSet(
            contributorCount: roster.contributors.count,
            inputAmount: 9_999,
            outputAmount: 10_000
        )
        #expect(
            throws: OpalV0.UnsignedTransactionTranscript.ValidationError
                .outputAmountExceedsInput(
                    inputSatoshis: 9_999,
                    outputSatoshis: 10_000
                )
        ) {
            _ = try makeTranscript(roster: roster, componentSet: overspent)
        }
    }

    @Test("Reject aggregate input or output value above the BCH money range")
    func rejectAggregateAmountsAboveMaximum() throws {
        let roster = try makeRoster(candidateCount: 7)
        let maximum = OpalV0.maximumMoneySatoshis
        let excessiveInputs = try paddedComponentSet(
            contributorCount: roster.contributors.count,
            leading: [
                try inputComponent(
                    salt: 0,
                    transaction: 1,
                    output: 0,
                    amount: maximum
                ),
                try inputComponent(
                    salt: 1,
                    transaction: 2,
                    output: 0,
                    amount: 1
                ),
                try outputComponent(
                    salt: 2,
                    fill: 0x31,
                    amount: maximum
                ),
            ]
        )
        #expect(
            throws: OpalV0.UnsignedTransactionTranscript.ValidationError
                .inputAmountExceedsMaximum(actual: maximum + 1)
        ) {
            _ = try makeTranscript(
                roster: roster,
                componentSet: excessiveInputs
            )
        }

        let excessiveOutputs = try paddedComponentSet(
            contributorCount: roster.contributors.count,
            leading: [
                try inputComponent(
                    salt: 0,
                    transaction: 1,
                    output: 0,
                    amount: maximum
                ),
                try outputComponent(
                    salt: 1,
                    fill: 0x31,
                    amount: maximum
                ),
                try outputComponent(
                    salt: 2,
                    fill: 0x32,
                    amount: 1
                ),
            ]
        )
        #expect(
            throws: OpalV0.UnsignedTransactionTranscript.ValidationError
                .outputAmountExceedsMaximum(actual: maximum + 1)
        ) {
            _ = try makeTranscript(
                roster: roster,
                componentSet: excessiveOutputs
            )
        }

        let completeExcessiveInputTotal = try paddedComponentSet(
            contributorCount: roster.contributors.count,
            leading: [
                try inputComponent(
                    salt: 0,
                    transaction: 1,
                    output: 0,
                    amount: maximum
                ),
                try inputComponent(
                    salt: 1,
                    transaction: 2,
                    output: 0,
                    amount: 1
                ),
                try inputComponent(
                    salt: 2,
                    transaction: 3,
                    output: 0,
                    amount: 2
                ),
                try outputComponent(
                    salt: 3,
                    fill: 0x33,
                    amount: maximum
                ),
            ]
        )
        #expect(
            throws: OpalV0.UnsignedTransactionTranscript.ValidationError
                .inputAmountExceedsMaximum(actual: maximum + 3)
        ) {
            _ = try makeTranscript(
                roster: roster,
                componentSet: completeExcessiveInputTotal
            )
        }
    }

    @Test("Bind component-set identity even when transaction bytes are unchanged")
    func bindComponentSetDigest() throws {
        let roster = try makeRoster(candidateCount: 7)
        let first = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: roster,
            manifest: manifest,
            componentSaltOffset: 0
        )
        let second = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: roster,
            manifest: manifest,
            componentSaltOffset: 500
        )

        #expect(
            first.transcript.unsignedTransactionBytes
                == second.transcript.unsignedTransactionBytes
        )
        #expect(first.componentSet.digest != second.componentSet.digest)
        #expect(
            first.transcript.transcriptRoot
                != second.transcript.transcriptRoot
        )
    }

    private let manifest = try! Attempt.ManifestBinding(
        validatedRoundIdentifier: Array(repeating: 0xA1, count: 32),
        validatedManifestDigest: Array(repeating: 0xA2, count: 32)
    )

    private func makeRoster(
        candidateCount: Int,
        identityOffset: UInt8 = 0
    ) throws -> Attempt.Roster {
        try MosaicRoleElectionFixtures.makeElection(
            controlIdentities: (0 ..< candidateCount).map { index in
                MosaicManifestSignatureFixtures.controlIdentity(
                    scalarByte: identityOffset &+ UInt8(index + 1)
                )
            },
            profile: .opalV0
        ).result.roster
    }

    private func makeCommitmentValidation(
        roster: Attempt.Roster
    ) throws -> Attempt.CommitmentSetValidation {
        return try Attempt.CommitmentSetValidation(
            profile: .opalV0,
            roster: roster,
            commitmentSet: MosaicUnsignedTransactionTranscriptFixtures
                .makeCommitmentSet(
                    contributorCount: roster.contributors.count
                )
        )
    }

    private func makeTranscript(
        roster: Attempt.Roster,
        commitmentValidation: Attempt.CommitmentSetValidation? = nil,
        componentSet: OpalV0.ComponentSet
    ) throws -> OpalV0.UnsignedTransactionTranscript {
        let resolvedCommitmentValidation: Attempt.CommitmentSetValidation
        if let commitmentValidation {
            resolvedCommitmentValidation = commitmentValidation
        } else {
            resolvedCommitmentValidation = try makeCommitmentValidation(
                roster: roster
            )
        }
        return try OpalV0.UnsignedTransactionTranscript(
            roster: roster,
            manifest: manifest,
            commitmentSet: resolvedCommitmentValidation,
            componentSet: componentSet
        )
    }

    private func makeSingleInputOutputSet(
        contributorCount: Int,
        inputAmount: UInt64,
        outputAmount: UInt64
    ) throws -> OpalV0.ComponentSet {
        try paddedComponentSet(
            contributorCount: contributorCount,
            leading: [
                try .init(
                    saltCommitment: indexedDigest(0),
                    payload: .input(
                        try .init(
                            previousTransactionHash: indexedDigest(1_000),
                            outputIndex: 3,
                            amountSatoshis: inputAmount
                        )
                    )
                ),
                try .init(
                    saltCommitment: indexedDigest(1),
                    payload: .output(
                        try .init(
                            lockingScript: p2pkh(fill: 0x66),
                            amountSatoshis: outputAmount
                        )
                    )
                ),
            ]
        )
    }

    private func makeOrderedComponentSet(
        contributorCount: Int
    ) throws -> OpalV0.ComponentSet {
        try paddedComponentSet(
            contributorCount: contributorCount,
            leading: [
                try inputComponent(salt: 0, transaction: 5, output: 4, amount: 2_501),
                try inputComponent(salt: 1, transaction: 4, output: 9, amount: 2_000),
                try inputComponent(salt: 2, transaction: 4, output: 2, amount: 1_000),
                try outputComponent(salt: 3, fill: 0x20, amount: 2_500),
                try outputComponent(salt: 4, fill: 0x10, amount: 2_500),
            ].reversed()
        )
    }

    private func inputComponent(
        salt: Int,
        transaction: Int,
        output: UInt32,
        amount: UInt64
    ) throws -> OpalV0.Component {
        try .init(
            saltCommitment: indexedDigest(salt),
            payload: .input(
                try .init(
                    previousTransactionHash: indexedDigest(transaction),
                    outputIndex: output,
                    amountSatoshis: amount
                )
            )
        )
    }

    private func outputComponent(
        salt: Int,
        fill: UInt8,
        amount: UInt64
    ) throws -> OpalV0.Component {
        try .init(
            saltCommitment: indexedDigest(salt),
            payload: .output(
                try .init(
                    lockingScript: p2pkh(fill: fill),
                    amountSatoshis: amount
                )
            )
        )
    }

    private func paddedComponentSet(
        contributorCount: Int,
        leading: some Sequence<OpalV0.Component>
    ) throws -> OpalV0.ComponentSet {
        var components = Array(leading)
        let memberCount = contributorCount
            * OpalV0.componentAuthorizationCountPerContributor
        components.append(
            contentsOf: try (components.count ..< memberCount).map { index in
                try .init(
                    saltCommitment: indexedDigest(index),
                    payload: .blank
                )
            }
        )
        return try .init(components: components)
    }

    private func indexedDigest(_ index: Int) -> [UInt8] {
        MosaicUnsignedTransactionTranscriptFixtures.indexedDigest(index)
    }

    private func p2pkh(fill: UInt8) -> [UInt8] {
        MosaicUnsignedTransactionTranscriptFixtures.p2pkhLockingScript(fill: fill)
    }

    private func hexadecimal(_ bytes: [UInt8]) -> String {
        MosaicOpalV0WireContractValidator.hexadecimal(bytes)
    }

    private struct RejectingTranscriptInclusionValidator:
        LocalAttempt.TranscriptInclusionValidating
    {
        struct Rejection: Error {}

        func validateCompleteInclusion(
            attemptIdentifier: LocalAttempt.AttemptIdentifier,
            generationIdentifier: LocalAttempt.GenerationIdentifier,
            contributor: Attempt.ControlIdentity,
            materialIdentifier: LocalAttempt.MaterialIdentifier,
            transcript: OpalV0.UnsignedTransactionTranscript
        ) throws {
            throw Rejection()
        }
    }
}
