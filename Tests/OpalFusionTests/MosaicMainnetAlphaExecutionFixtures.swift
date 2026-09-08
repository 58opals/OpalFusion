// MosaicMainnetAlphaExecutionFixtures.swift

import Foundation
import OpalCrypto
@testable import OpalFusion

enum MosaicMainnetAlphaExecutionFixtures {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias Host = OpalFusion.Host
    typealias Session = Alpha.RuntimeSession

    struct Outpoint: Hashable, Sendable {
        let transactionHash: [UInt8]
        let outputIndex: UInt32

        init(transactionHash: [UInt8], outputIndex: UInt32) {
            self.transactionHash = transactionHash
            self.outputIndex = outputIndex
        }

        init(_ input: Host.ParticipantInput) {
            transactionHash = input.outpointTransactionHashBytes
            outputIndex = input.outpointIndex
        }
    }

    struct PreviousOutputSource: Host.MosaicPreviousOutputSource {
        enum SourceError: Error {
            case missingOutput
        }

        let inputsByOutpoint: [Outpoint: Host.ParticipantInput]

        func resolvePreviousOutputs(
            for requests: [Host.MosaicPreviousOutputRequest]
        ) async throws -> [Host.MosaicPreviousOutput] {
            try requests.map { request in
                guard let input = inputsByOutpoint[
                    Outpoint(
                        transactionHash: request.transactionHashBytes,
                        outputIndex: request.outputIndex
                    )
                ] else {
                    throw SourceError.missingOutput
                }
                return try .init(
                    transactionHashBytes: request.transactionHashBytes,
                    outputIndex: request.outputIndex,
                    amountSatoshis: input.amountSatoshis,
                    lockingScriptBytes: input.lockingScriptBytes,
                    tokenState: .absent
                )
            }
        }
    }

    struct Prepared {
        let admission: Fixture.Harness
        let session: Session
        let materialized: MosaicMainnetAlphaFixtures.MaterializedPreparation
        let localMaterial: Alpha.LocalContributionMaterial
        let localAuthorizationResponseSet: Alpha.AuthorizationResponseSet
        let localAuthorizationValidation:
            Alpha.AuthorizationResponseSetMaterialValidation
        let acknowledgementSet: Alpha.PreSignAcknowledgementSet
        let previousOutputSource: PreviousOutputSource
        let previousOutputs: Alpha.PreviousOutputResolver.Validation
        let signingRequest: Host.MosaicTransactionSigningRequest
        let localFinalizedTransaction: Host.FinalizedTransaction
        let signatureSet: Alpha.BCHSignatureSet
        let completePayload: Alpha.CompleteTransactionPayload
    }

    struct Completion {
        let previousOutputSource: PreviousOutputSource
        let previousOutputs: Alpha.PreviousOutputResolver.Validation
        let signatureSet: Alpha.BCHSignatureSet
        let completePayload: Alpha.CompleteTransactionPayload
    }

    static func makeCompletion(
        admission: Fixture.Harness,
        materialized: MosaicMainnetAlphaFixtures.MaterializedPreparation
    ) async throws -> Completion {
        let transcript = materialized.prepared.transcript
        let source = PreviousOutputSource(
            inputsByOutpoint: Dictionary(
                uniqueKeysWithValues: materialized.materials.values.flatMap {
                    material in
                    material.reservationLease.participantReservation.inputs.map {
                        (Outpoint($0), $0)
                    }
                }
            )
        )
        let previousOutputs = try await Alpha.PreviousOutputResolver(
            source: source
        ).resolve(for: transcript)
        let signatureSet = try makeSignatureSet(
            admission: admission,
            materialized: materialized,
            previousOutputs: previousOutputs
        )
        let completeTransaction = try Alpha.CompleteTransactionAssembler
            .assemble(
                transcript: transcript,
                signatureSet: signatureSet,
                spentInputs: previousOutputs.spentInputs
            )
        let completePayload = try Alpha.CompleteTransactionPayload(
            roundIdentifier: admission.manifest.core.roundIdentifier,
            transcriptRoot: transcript.transcriptRoot.validatedBytes,
            completeTransaction: completeTransaction
        )
        return .init(
            previousOutputSource: source,
            previousOutputs: previousOutputs,
            signatureSet: signatureSet,
            completePayload: completePayload
        )
    }

    static func reservationRequest(
        for eligibility: Alpha.ReservationCoordinator.ReservationEligibility,
        expiresAt: Date
    ) throws -> Host.MosaicReservationRequest {
        let manifest = eligibility.manifest
        return try .init(
            attemptIdentifier: eligibility.context.attemptIdentifier.validatedBytes,
            networkGenesisHash: manifest.core.networkGenesisHash,
            roundIdentifier: manifest.core.roundIdentifier,
            expiresAt: expiresAt,
            componentCount: Int(manifest.core.componentCount),
            feeRateSatoshisPerByte: manifest.core.feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis:
                manifest.core.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis:
                manifest.core.maximumExcessFeeSatoshis,
            requiredExcessFeeSatoshis: try Alpha.ContributionFeePolicy
                .requiredExcessFeeSatoshis(
                    for: eligibility.context.localControlIdentity,
                    in: eligibility.context.roster
                ),
            transactionProfileIdentifier:
                manifest.core.transactionProfileIdentifier
        )
    }

    private static func makeSignatureSet(
        admission: Fixture.Harness,
        materialized: MosaicMainnetAlphaFixtures.MaterializedPreparation,
        previousOutputs: Alpha.PreviousOutputResolver.Validation
    ) throws -> Alpha.BCHSignatureSet {
        var signingKeysByOutpoint: [Outpoint: OpalCrypto.Secp256k1.SigningKey]
            = [:]
        for (contributorIndex, contributor) in admission.manifest.core
            .orderedContributors.enumerated() {
            let material = try require(materialized.materials[contributor])
            let key = try OpalCrypto.Secp256k1.SigningKey(
                rawRepresentation: scalarBytes(10_000 + contributorIndex)
            )
            for input in material.reservationLease.participantReservation.inputs {
                signingKeysByOutpoint[Outpoint(input)] = key
            }
        }
        let transcript = materialized.prepared.transcript
        let entries = try previousOutputs.spentInputs.enumerated().map {
            inputIndex, input in
            let key = try require(signingKeysByOutpoint[Outpoint(input)])
            let digest = try transcript.transaction.signatureHash(
                forInputAt: inputIndex,
                lockingScript: input.lockingScriptBytes,
                amountSatoshis: input.amountSatoshis,
                sighashType: 0x41
            )
            let signature = try key.signSchnorr(
                digest: .init(rawRepresentation: Data(digest))
            )
            return try Alpha.BCHSignatureEntry(
                inputIndex: UInt32(inputIndex),
                signature: [UInt8](signature.rawRepresentation),
                publicKey: [UInt8](key.publicKey.compressedRepresentation)
            )
        }
        return try .init(
            roundIdentifier: admission.manifest.core.roundIdentifier,
            transcriptRoot: transcript.transcriptRoot.validatedBytes,
            entries: entries,
            expectedInputCount: transcript.transaction.inputs.count
        )
    }

    static func unlockingScript(for entry: Alpha.BCHSignatureEntry) -> [UInt8] {
        [0x41] + entry.signature + [0x41, 0x21] + entry.publicKey
    }

    private static func scalarBytes(_ scalar: Int) -> Data {
        precondition(scalar > 0)
        var value = UInt32(scalar).bigEndian
        var result = Data(repeating: 0, count: 28)
        withUnsafeBytes(of: &value) { result.append(contentsOf: $0) }
        return result
    }

    static func require<Value>(_ value: Value?) throws -> Value {
        guard let value else {
            throw FixtureError.missingValue
        }
        return value
    }

    private enum FixtureError: Error {
        case missingValue
    }
}
