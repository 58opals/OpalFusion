// MosaicHostContractValidator.swift

import Foundation
@testable import OpalFusion
import Testing

@Suite("Mosaic wallet-host contract")
struct MosaicHostContractValidator {
    @Test("Valid manifest-bound reservation and signing values preserve their bindings")
    func preserveValidManifestAndTranscriptBindings() throws {
        let request = try makeReservationRequest()
        let referenceIdentifier = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )
        let reference = OpalFusion.Host.MosaicReservationReference(
            identifier: referenceIdentifier,
            generation: 7
        )
        let participant = OpalFusion.Host.ParticipantReservation(
            inputs: [makeInput()],
            outputs: [makeOutput()]
        )
        let lease = try OpalFusion.Host.MosaicReservationLease(
            reference: reference,
            expiresAt: request.expiresAt,
            participantReservation: participant
        )
        let signingRequest = try OpalFusion.Host.MosaicTransactionSigningRequest(
            reservationReference: reference,
            roundIdentifier: request.roundIdentifier,
            transcriptBinding: try makeTranscriptBinding(
                unsignedTransactionBytes: [0x02, 0x00]
            ),
            unsignedTransactionBytes: [0x02, 0x00],
            spentInputs: participant.inputs,
            localInputIndices: [0],
            expectedLocalOutputs: participant.outputs,
            feeRateSatoshisPerByte: request.feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis: request.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: request.maximumExcessFeeSatoshis,
            transactionProfileIdentifier: request.transactionProfileIdentifier
        )

        #expect(lease.reference == reference)
        #expect(signingRequest.reservationReference == reference)
        #expect(signingRequest.roundIdentifier == request.roundIdentifier)
        #expect(signingRequest.localInputIndices == [0])
        #expect(signingRequest.transcriptRoot == signingRequest.transcriptBinding.transcriptRoot)
    }

    @Test("Transcript bindings reject malformed digests, wrong roots, and substituted transactions")
    func rejectInvalidTranscriptBindings() throws {
        #expect(
            throws: OpalFusion.Host.MosaicHostContractError
                .invalidManifestDigestLength(actual: 31)
        ) {
            _ = try makeTranscriptBinding(
                manifestDigest: Array(repeating: 0x41, count: 31),
                unsignedTransactionBytes: [0x02]
            )
        }
        #expect(
            throws: OpalFusion.Host.MosaicHostContractError
                .invalidCommitmentSetDigestLength(actual: 31)
        ) {
            _ = try makeTranscriptBinding(
                commitmentSetDigest: Array(repeating: 0x42, count: 31),
                unsignedTransactionBytes: [0x02]
            )
        }
        #expect(
            throws: OpalFusion.Host.MosaicHostContractError
                .invalidComponentSetDigestLength(actual: 33)
        ) {
            _ = try makeTranscriptBinding(
                componentSetDigest: Array(repeating: 0x43, count: 33),
                unsignedTransactionBytes: [0x02]
            )
        }
        #expect(throws: OpalFusion.Host.MosaicHostContractError.emptyUnsignedTransaction) {
            _ = try makeTranscriptBinding(unsignedTransactionBytes: [])
        }

        #expect(
            throws: OpalFusion.Host.MosaicHostContractError
                .invalidTranscriptRootLength(actual: 31)
        ) {
            _ = try OpalFusion.Host.MosaicTranscriptBinding(
                profile: .opalV0,
                manifestDigest: Array(repeating: 0x41, count: 32),
                commitmentSetDigest: Array(repeating: 0x42, count: 32),
                componentSetDigest: Array(repeating: 0x43, count: 32),
                unsignedTransactionBytes: [0x02],
                acknowledgedTranscriptRoot: Array(repeating: 0, count: 31)
            )
        }

        #expect(throws: OpalFusion.Host.MosaicHostContractError.transcriptRootMismatch) {
            _ = try OpalFusion.Host.MosaicTranscriptBinding(
                profile: .opalV0,
                manifestDigest: Array(repeating: 0x41, count: 32),
                commitmentSetDigest: Array(repeating: 0x42, count: 32),
                componentSetDigest: Array(repeating: 0x43, count: 32),
                unsignedTransactionBytes: [0x02],
                acknowledgedTranscriptRoot: Array(repeating: 0, count: 32)
            )
        }

        let reference = OpalFusion.Host.MosaicReservationReference(
            identifier: UUID(),
            generation: 4
        )
        let binding = try makeTranscriptBinding(unsignedTransactionBytes: [0x02])
        #expect(
            throws: OpalFusion.Host.MosaicHostContractError
                .unsignedTransactionTranscriptMismatch
        ) {
            _ = try OpalFusion.Host.MosaicTransactionSigningRequest(
                reservationReference: reference,
                roundIdentifier: Array(repeating: 0x33, count: 32),
                transcriptBinding: binding,
                unsignedTransactionBytes: [0x03],
                spentInputs: [makeInput()],
                localInputIndices: [0],
                expectedLocalOutputs: [makeOutput()],
                feeRateSatoshisPerByte: 1,
                minimumExcessFeeSatoshis: 100,
                maximumExcessFeeSatoshis: 200,
                transactionProfileIdentifier: "mosaic-bch-p2pkh-draft"
            )
        }

        let commonManifest = Array(repeating: UInt8(0x41), count: 32)
        let commonCommitments = Array(repeating: UInt8(0x42), count: 32)
        let commonComponents = Array(repeating: UInt8(0x43), count: 32)
        let draftRoot = try OpalFusion.Host.MosaicTranscriptBinding.transcriptRoot(
            profile: .draft1,
            manifestDigest: commonManifest,
            commitmentSetDigest: commonCommitments,
            componentSetDigest: commonComponents,
            unsignedTransactionBytes: [0x02]
        )
        let opalRoot = try OpalFusion.Host.MosaicTranscriptBinding.transcriptRoot(
            profile: .opalV0,
            manifestDigest: commonManifest,
            commitmentSetDigest: commonCommitments,
            componentSetDigest: commonComponents,
            unsignedTransactionBytes: [0x02]
        )
        #expect(draftRoot != opalRoot)
    }

    @Test("Reservation requests reject malformed attempt, network, round, and profile bindings")
    func rejectMalformedReservationBindings() throws {
        #expect(throws: OpalFusion.Host.MosaicHostContractError.emptyAttemptIdentifier) {
            _ = try makeReservationRequest(attemptIdentifier: [])
        }
        #expect(
            throws: OpalFusion.Host.MosaicHostContractError
                .invalidNetworkGenesisHashLength(actual: 31)
        ) {
            _ = try makeReservationRequest(networkGenesisHash: Array(repeating: 0x22, count: 31))
        }
        #expect(
            throws: OpalFusion.Host.MosaicHostContractError
                .invalidRoundIdentifierLength(actual: 33)
        ) {
            _ = try makeReservationRequest(roundIdentifier: Array(repeating: 0x33, count: 33))
        }
        #expect(throws: OpalFusion.Host.MosaicHostContractError.nonASCIITransactionProfileIdentifier) {
            _ = try makeReservationRequest(transactionProfileIdentifier: "draft-π")
        }
    }

    @Test("Reservation requests reject invalid component and excess-fee constraints")
    func rejectInvalidReservationConstraints() throws {
        #expect(
            throws: OpalFusion.Host.MosaicHostContractError.invalidComponentCount(actual: 0)
        ) {
            _ = try makeReservationRequest(componentCount: 0)
        }
        #expect(
            throws: OpalFusion.Host.MosaicHostContractError
                .invalidExcessFeeRange(minimum: 10, maximum: 9)
        ) {
            _ = try makeReservationRequest(
                minimumExcessFeeSatoshis: 10,
                maximumExcessFeeSatoshis: 9
            )
        }
    }

    @Test("Reservation leases require both wallet inputs and fresh outputs")
    func rejectEmptyReservationMaterial() throws {
        let reference = OpalFusion.Host.MosaicReservationReference(
            identifier: UUID(),
            generation: 1
        )
        #expect(throws: OpalFusion.Host.MosaicHostContractError.emptyReservationInputs) {
            _ = try OpalFusion.Host.MosaicReservationLease(
                reference: reference,
                expiresAt: .now,
                participantReservation: .init(inputs: [], outputs: [makeOutput()])
            )
        }
        #expect(throws: OpalFusion.Host.MosaicHostContractError.emptyReservationOutputs) {
            _ = try OpalFusion.Host.MosaicReservationLease(
                reference: reference,
                expiresAt: .now,
                participantReservation: .init(inputs: [makeInput()], outputs: [])
            )
        }
    }

    @Test("Signing requests reject duplicate and out-of-range local input assignments")
    func rejectInvalidLocalInputAssignments() throws {
        let reference = OpalFusion.Host.MosaicReservationReference(
            identifier: UUID(),
            generation: 2
        )
        #expect(
            throws: OpalFusion.Host.MosaicHostContractError.duplicateLocalInputIndex(0)
        ) {
            _ = try makeSigningRequest(reference: reference, localInputIndices: [0, 0])
        }
        #expect(
            throws: OpalFusion.Host.MosaicHostContractError
                .localInputIndexOutOfBounds(index: 1, inputCount: 1)
        ) {
            _ = try makeSigningRequest(reference: reference, localInputIndices: [1])
        }
        #expect(throws: OpalFusion.Host.MosaicHostContractError.emptyLocalInputIndices) {
            _ = try makeSigningRequest(reference: reference, localInputIndices: [])
        }
    }

    @Test("Signing requests reject malformed spent inputs and expected local outputs")
    func rejectMalformedSigningMaterial() throws {
        let reference = OpalFusion.Host.MosaicReservationReference(
            identifier: UUID(),
            generation: 3
        )
        let malformedInput = OpalFusion.Host.ParticipantInput(
            outpointTransactionHashBytes: [0x01],
            outpointIndex: 0,
            amountSatoshis: 1,
            lockingScriptBytes: [0x51]
        )
        #expect(
            throws: OpalFusion.Host.MosaicHostContractError
                .invalidSpentInputHashLength(index: 0, actual: 1)
        ) {
            _ = try makeSigningRequest(reference: reference, spentInputs: [malformedInput])
        }

        let zeroOutput = OpalFusion.Host.ParticipantOutput(
            lockingScriptBytes: [0x51],
            amountSatoshis: 0
        )
        #expect(
            throws: OpalFusion.Host.MosaicHostContractError
                .zeroExpectedLocalOutputAmount(index: 0)
        ) {
            _ = try makeSigningRequest(
                reference: reference,
                expectedLocalOutputs: [zeroOutput]
            )
        }
    }

    @Test("Complete transactions require broadcastable bytes distinct from local signing output")
    func validateCompleteTransactionBoundary() throws {
        #expect(throws: OpalFusion.Host.MosaicHostContractError.emptyCompleteTransaction) {
            _ = try OpalFusion.Host.MosaicCompleteTransaction(transactionBytes: [])
        }

        let transaction = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: [0x02, 0x00]
        )
        #expect(transaction.transactionBytes == [0x02, 0x00])
    }

}
