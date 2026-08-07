// MosaicHostContractValidator+Fixtures.swift

import Foundation
@testable import OpalFusion

extension MosaicHostContractValidator {
    func makeReservationRequest(
        attemptIdentifier: [UInt8] = [0x11],
        networkGenesisHash: [UInt8] = Array(repeating: 0x22, count: 32),
        roundIdentifier: [UInt8] = Array(repeating: 0x33, count: 32),
        componentCount: Int = 2,
        minimumExcessFeeSatoshis: UInt64 = 100,
        maximumExcessFeeSatoshis: UInt64 = 200,
        transactionProfileIdentifier: String = "mosaic-bch-p2pkh-draft"
    ) throws -> OpalFusion.Host.MosaicReservationRequest {
        try .init(
            attemptIdentifier: attemptIdentifier,
            networkGenesisHash: networkGenesisHash,
            roundIdentifier: roundIdentifier,
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            componentCount: componentCount,
            feeRateSatoshisPerByte: 1,
            minimumExcessFeeSatoshis: minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: maximumExcessFeeSatoshis,
            transactionProfileIdentifier: transactionProfileIdentifier
        )
    }

    func makeSigningRequest(
        reference: OpalFusion.Host.MosaicReservationReference,
        localInputIndices: [Int] = [0],
        spentInputs: [OpalFusion.Host.ParticipantInput]? = nil,
        expectedLocalOutputs: [OpalFusion.Host.ParticipantOutput]? = nil
    ) throws -> OpalFusion.Host.MosaicTransactionSigningRequest {
        let unsignedTransactionBytes: [UInt8] = [0x02]
        return try .init(
            reservationReference: reference,
            roundIdentifier: Array(repeating: 0x33, count: 32),
            transcriptBinding: try makeTranscriptBinding(
                unsignedTransactionBytes: unsignedTransactionBytes
            ),
            unsignedTransactionBytes: unsignedTransactionBytes,
            spentInputs: spentInputs ?? [makeInput()],
            localInputIndices: localInputIndices,
            expectedLocalOutputs: expectedLocalOutputs ?? [makeOutput()],
            feeRateSatoshisPerByte: 1,
            minimumExcessFeeSatoshis: 100,
            maximumExcessFeeSatoshis: 200,
            transactionProfileIdentifier: "mosaic-bch-p2pkh-draft"
        )
    }

    func makeTranscriptBinding(
        profile: OpalFusion.Mosaic.Profile = .draft1,
        manifestDigest: [UInt8] = Array(repeating: 0x41, count: 32),
        commitmentSetDigest: [UInt8] = Array(repeating: 0x42, count: 32),
        componentSetDigest: [UInt8] = Array(repeating: 0x43, count: 32),
        unsignedTransactionBytes: [UInt8]
    ) throws -> OpalFusion.Host.MosaicTranscriptBinding {
        let root = try OpalFusion.Host.MosaicTranscriptBinding.transcriptRoot(
            profile: profile,
            manifestDigest: manifestDigest,
            commitmentSetDigest: commitmentSetDigest,
            componentSetDigest: componentSetDigest,
            unsignedTransactionBytes: unsignedTransactionBytes
        )
        return try .init(
            profile: profile,
            manifestDigest: manifestDigest,
            commitmentSetDigest: commitmentSetDigest,
            componentSetDigest: componentSetDigest,
            unsignedTransactionBytes: unsignedTransactionBytes,
            acknowledgedTranscriptRoot: root
        )
    }

    func makeInput() -> OpalFusion.Host.ParticipantInput {
        .init(
            outpointTransactionHashBytes: Array(repeating: 0x55, count: 32),
            outpointIndex: 0,
            amountSatoshis: 100_000,
            lockingScriptBytes: [0x76, 0xa9, 0x14],
            publicKey: Array(repeating: 0x02, count: 33)
        )
    }

    func makeOutput() -> OpalFusion.Host.ParticipantOutput {
        .init(lockingScriptBytes: [0x76, 0xa9, 0x14], amountSatoshis: 99_000)
    }
}
