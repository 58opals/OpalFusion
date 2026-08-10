// MosaicMainnetAlphaBCHCompletionValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha BCH completion")
struct MosaicMainnetAlphaBCHCompletionValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Fixture = MosaicMainnetAlphaBCHCompletionFixtures

    enum SignatureSubstitution: CaseIterable, Sendable {
        case foreignTranscript
        case nonInputComponent
        case wrongInputIndex
        case wrongLockingScript
        case wrongSignature
    }

    @Test("Accept exact previous-output-backed BCH signature and transaction")
    func acceptExactSignatureAndTransaction() async throws {
        let prepared = try await Fixture.prepare()
        let validator = Alpha.BCHSignatureAdmissionValidator(
            previousOutputs: prepared.previousOutputs
        )

        try validator.validateBCHSignatureAdmission(
            submission: prepared.submission,
            acceptedInputComponent: prepared.acceptedInput,
            transcript: prepared.transcript
        )
        let candidate = try Alpha.CompleteTransactionCandidate(
            attemptIdentifier: .init(
                validatedBytes: [UInt8](repeating: 0xA1, count: 32)
            ),
            generationIdentifier: .init(
                opaqueBytes: [UInt8](repeating: 0xA2, count: 32)
            ),
            materialIdentifier: .init(
                opaqueBytes: [UInt8](repeating: 0xA3, count: 32)
            ),
            transcript: prepared.transcript,
            signatureSet: prepared.signatureSet,
            payload: prepared.payload
        )
        let validation = try Alpha.CompleteTransactionValidation(
            validating: candidate,
            previousOutputs: prepared.previousOutputs
        )

        #expect(validation.candidate == candidate)
        #expect(validation.completeTransaction == prepared.payload.completeTransaction)
    }

    @Test(
        "Reject substituted BCH signature authority",
        arguments: SignatureSubstitution.allCases
    )
    func rejectSignatureSubstitution(
        _ substitution: SignatureSubstitution
    ) async throws {
        let prepared = try await Fixture.prepare()
        let transcript = prepared.transcript
        var previousOutputs = prepared.previousOutputs
        var acceptedComponent = prepared.acceptedInput
        var submission = prepared.submission
        var expectedFailure = Alpha.BCHSignatureAdmissionValidator.Failure
            .signatureRejected

        switch substitution {
        case .foreignTranscript:
            let foreign = try await Fixture.prepare(componentSaltOffset: 1)
            previousOutputs = foreign.previousOutputs
            expectedFailure = .transcriptMismatch

        case .nonInputComponent:
            acceptedComponent = try #require(
                prepared.transcript.componentSet.components.first {
                    if case .output = $0.payload {
                        return true
                    }
                    return false
                }
            )
            expectedFailure = .inputComponentMissing

        case .wrongInputIndex:
            submission = try .init(
                transcriptRoot: submission.transcriptRoot,
                authorizationToken: submission.authorizationToken,
                entry: .init(
                    inputIndex: 1,
                    signature: submission.entry.signature,
                    publicKey: submission.entry.publicKey
                )
            )
            expectedFailure = .inputComponentMissing

        case .wrongLockingScript:
            previousOutputs = try await Fixture.resolve(
                transcript: prepared.transcript,
                lockingScript:
                    MosaicUnsignedTransactionTranscriptFixtures
                        .p2pkhLockingScript(fill: 0x55)
            )

        case .wrongSignature:
            let signingKey = try OpalCrypto.Secp256k1.SigningKey(
                rawRepresentation: Data(repeating: 0, count: 31) + Data([11])
            )
            let signature = try signingKey.signSchnorr(
                digest: .init(rawRepresentation: Data(repeating: 0xD5, count: 32))
            )
            submission = try .init(
                transcriptRoot: submission.transcriptRoot,
                authorizationToken: submission.authorizationToken,
                entry: .init(
                    inputIndex: 0,
                    signature: [UInt8](signature.rawRepresentation),
                    publicKey: submission.entry.publicKey
                )
            )
        }

        let validator = Alpha.BCHSignatureAdmissionValidator(
            previousOutputs: previousOutputs
        )
        #expect(throws: expectedFailure) {
            try validator.validateBCHSignatureAdmission(
                submission: submission,
                acceptedInputComponent: acceptedComponent,
                transcript: transcript
            )
        }
    }

    @Test("Complete validation distinguishes transcript and assembly failures")
    func rejectInvalidCompleteTransactionAuthority() async throws {
        let prepared = try await Fixture.prepare()
        let candidate = try Alpha.CompleteTransactionCandidate(
            attemptIdentifier: .init(
                validatedBytes: [UInt8](repeating: 0xB1, count: 32)
            ),
            generationIdentifier: .init(
                opaqueBytes: [UInt8](repeating: 0xB2, count: 32)
            ),
            materialIdentifier: .init(
                opaqueBytes: [UInt8](repeating: 0xB3, count: 32)
            ),
            transcript: prepared.transcript,
            signatureSet: prepared.signatureSet,
            payload: prepared.payload
        )
        let foreign = try await Fixture.prepare(componentSaltOffset: 1)
        #expect(
            throws: Alpha.CompleteTransactionValidation.ValidationError
                .previousOutputTranscriptMismatch
        ) {
            _ = try Alpha.CompleteTransactionValidation(
                validating: candidate,
                previousOutputs: foreign.previousOutputs
            )
        }
        let wrongScript = try await Fixture.resolve(
            transcript: prepared.transcript,
            lockingScript:
                MosaicUnsignedTransactionTranscriptFixtures
                    .p2pkhLockingScript(fill: 0x44)
        )
        #expect(
            throws: Alpha.CompleteTransactionValidation.ValidationError
                .assemblyFailed
        ) {
            _ = try Alpha.CompleteTransactionValidation(
                validating: candidate,
                previousOutputs: wrongScript
            )
        }
    }
}
