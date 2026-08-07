// MosaicOpalV0AuthorizationValidator.swift

import Foundation
import OpalCrypto
@testable import OpalFusion
import Testing

@Suite("Mosaic Opal v0 authorization")
struct MosaicOpalV0AuthorizationValidator {
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Ledger = OpalFusion.Mosaic.OpalV0.AuthorizationIssuanceLedger

    @Test("Wait for every contributor's 23 requests before evaluation")
    func waitForCompleteRequestSet() throws {
        let roster = try makeRoster()
        var ledger = Ledger(roster: roster)
        let firstMessage = try blindedMessage(1)

        #expect(
            ledger.apply(
                input: .request(
                    contributor: roster.contributors[0],
                    slot: 0,
                    blindedMessage: firstMessage
                )
            ).isEmpty
        )
        #expect(
            ledger.apply(
                input: .request(
                    contributor: roster.contributors[0],
                    slot: 0,
                    blindedMessage: firstMessage
                )
            ).isEmpty
        )

        let effects = try submitRemainingRequests(
            to: &ledger,
            roster: roster,
            skippingFirst: true
        )

        #expect(ledger.phase == .evaluating)
        #expect(effects.count == 6 * 23)
        guard case let .evaluate(firstEvaluation) = effects.first,
              case let .evaluate(lastEvaluation) = effects.last else {
            Issue.record("Expected a deterministically ordered evaluation batch.")
            return
        }
        #expect(firstEvaluation.key.contributor == roster.contributors[0])
        #expect(firstEvaluation.key.slot == 0)
        #expect(lastEvaluation.key.contributor == roster.contributors[5])
        #expect(lastEvaluation.key.slot == 22)
    }

    @Test("Cache exact requests and evaluation responses")
    func cacheExactRequestsAndResponses() throws {
        let roster = try makeRoster()
        var ledger = Ledger(roster: roster)
        let evaluations = try submitRemainingRequests(to: &ledger, roster: roster)
        let firstEvaluation = try evaluation(from: evaluations[0])
        let firstResponse = Ledger.Response(
            key: firstEvaluation.key,
            blindSignature: try blindSignature(0x61)
        )

        #expect(ledger.apply(input: .evaluated(firstResponse)) == [.deliver(firstResponse)])
        #expect(
            ledger.apply(
                input: .request(
                    contributor: firstEvaluation.key.contributor,
                    slot: firstEvaluation.key.slot,
                    blindedMessage: firstEvaluation.blindedMessage
                )
            ) == [.deliver(firstResponse)]
        )
        #expect(ledger.apply(input: .evaluated(firstResponse)) == [.deliver(firstResponse)])

        for effect in evaluations.dropFirst().dropLast() {
            let evaluation = try evaluation(from: effect)
            let response = Ledger.Response(
                key: evaluation.key,
                blindSignature: try blindSignature(UInt8(truncatingIfNeeded: evaluation.key.slot + 1))
            )
            #expect(ledger.apply(input: .evaluated(response)) == [.deliver(response)])
        }

        let finalEvaluation = try evaluation(from: evaluations.last!)
        let finalResponse = Ledger.Response(
            key: finalEvaluation.key,
            blindSignature: try blindSignature(0x7f)
        )
        #expect(
            ledger.apply(input: .evaluated(finalResponse))
                == [.deliver(finalResponse), .issuanceComplete]
        )
        #expect(ledger.phase == .issued)
    }

    @Test("Terminate on invalid contributors, slots, and slot reuse")
    func terminateOnInvalidRequests() throws {
        let roster = try makeRoster()

        var conductorLedger = Ledger(roster: roster)
        #expect(
            conductorLedger.apply(
                input: .request(
                    contributor: roster.conductor,
                    slot: 0,
                    blindedMessage: try blindedMessage(1)
                )
            ) == [.terminated(.conductorSubmittedAuthorization)]
        )
        #expect(
            conductorLedger.apply(
                input: .request(
                    contributor: roster.contributors[0],
                    slot: 0,
                    blindedMessage: try blindedMessage(1)
                )
            ) == [.inputRejected(.inputAfterTermination)]
        )

        var unknownLedger = Ledger(roster: roster)
        #expect(
            unknownLedger.apply(
                input: .request(
                    contributor: .init(validatedBytes: [0xff]),
                    slot: 0,
                    blindedMessage: try blindedMessage(1)
                )
            ) == [.terminated(.unknownContributor)]
        )

        var invalidSlotLedger = Ledger(roster: roster)
        #expect(
            invalidSlotLedger.apply(
                input: .request(
                    contributor: roster.contributors[0],
                    slot: 23,
                    blindedMessage: try blindedMessage(1)
                )
            ) == [.terminated(.invalidSlot(actual: 23))]
        )

        var conflictLedger = Ledger(roster: roster)
        _ = conflictLedger.apply(
            input: .request(
                contributor: roster.contributors[0],
                slot: 0,
                blindedMessage: try blindedMessage(1)
            )
        )
        let key = Ledger.RequestKey(contributor: roster.contributors[0], slot: 0)
        #expect(
            conflictLedger.apply(
                input: .request(
                    contributor: roster.contributors[0],
                    slot: 0,
                    blindedMessage: try blindedMessage(2)
                )
            ) == [.terminated(.conflictingSlotReuse(key))]
        )
    }

    @Test("Terminate on missing, conflicting, and failed evaluations")
    func terminateOnInvalidEvaluations() throws {
        let roster = try makeRoster()
        let firstKey = Ledger.RequestKey(contributor: roster.contributors[0], slot: 0)

        var earlyLedger = Ledger(roster: roster)
        let earlyResponse = Ledger.Response(
            key: firstKey,
            blindSignature: try blindSignature(1)
        )
        #expect(
            earlyLedger.apply(input: .evaluated(earlyResponse))
                == [.terminated(.unexpectedEvaluationResult(firstKey))]
        )

        var conflictLedger = Ledger(roster: roster)
        _ = try submitRemainingRequests(to: &conflictLedger, roster: roster)
        let firstResponse = Ledger.Response(
            key: firstKey,
            blindSignature: try blindSignature(1)
        )
        _ = conflictLedger.apply(input: .evaluated(firstResponse))
        let conflictingResponse = Ledger.Response(
            key: firstKey,
            blindSignature: try blindSignature(2)
        )
        #expect(
            conflictLedger.apply(input: .evaluated(conflictingResponse))
                == [.terminated(.conflictingEvaluationResult(firstKey))]
        )

        var failedLedger = Ledger(roster: roster)
        _ = try submitRemainingRequests(to: &failedLedger, roster: roster)
        #expect(
            failedLedger.apply(input: .evaluationFailed(firstKey))
                == [.terminated(.evaluationFailed(firstKey))]
        )
    }

    @Test("Fail closed when the RSABSSA evaluator is unavailable")
    func failClosedWithoutEvaluator() throws {
        #expect(throws: OpalFusion.Mosaic.OpalV0.AuthorizationEvaluator.Failure.unavailable) {
            _ = try OpalFusion.Mosaic.OpalV0.AuthorizationEvaluator.unavailable.evaluate(
                try blindedMessage(1)
            )
        }
    }

    @Test("Issue and verify one attempt-bound component authorization")
    func issueAndVerifyAuthorization() throws {
        let evaluator = try OpalFusion.Mosaic.OpalV0.AuthorizationEvaluator
            .generate()
        let verificationKey = try #require(evaluator.verificationKey)
        let input = try authorizationInput(
            verificationKey: verificationKey,
            nonceByte: 0x31
        )
        let request = try OpalFusion.Mosaic.OpalV0.AuthorizationRequest(
            input: input,
            using: verificationKey
        )
        let response = try evaluator.evaluate(request.blindedMessage)
        let token = try request.finalize(response)

        #expect(token.input == input)
        #expect(token.verify(using: verificationKey))
        #expect(token.spentIdentifier == input.spentIdentifier)
    }

    @Test("Reject substituted authorization keys and token material")
    func rejectSubstitutedAuthorizationMaterial() throws {
        let evaluator = try OpalFusion.Mosaic.OpalV0.AuthorizationEvaluator
            .generate()
        let verificationKey = try #require(evaluator.verificationKey)
        let otherKey = try OpalCrypto.RSABSSA.SigningKey.generate()
            .verificationKey
        let input = try authorizationInput(
            verificationKey: verificationKey,
            nonceByte: 0x41
        )

        #expect(
            throws: OpalFusion.Mosaic.OpalV0.AuthorizationRequest.Failure
                .verificationKeyIdentifierMismatch
        ) {
            _ = try OpalFusion.Mosaic.OpalV0.AuthorizationRequest(
                input: input,
                using: otherKey
            )
        }

        let request = try OpalFusion.Mosaic.OpalV0.AuthorizationRequest(
            input: input,
            using: verificationKey
        )
        #expect(throws: OpalCrypto.RSABSSA.Error.invalidBlindSignature) {
            _ = try request.finalize(
                .init(rawRepresentation: Data(repeating: 0, count: 256))
            )
        }
        let token = try request.finalize(
            evaluator.evaluate(request.blindedMessage)
        )
        #expect(!token.verify(using: otherKey))

        let alteredInput = try authorizationInput(
            verificationKey: verificationKey,
            nonceByte: 0x42
        )
        let inputSubstitution = OpalFusion.Mosaic.OpalV0.AuthorizationToken(
            input: alteredInput,
            messageRandomizer: token.messageRandomizer,
            signature: token.signature
        )
        #expect(!inputSubstitution.verify(using: verificationKey))

        var alteredSignature = token.signature.rawRepresentation
        alteredSignature[alteredSignature.startIndex] ^= 0x01
        let signatureSubstitution = OpalFusion.Mosaic.OpalV0.AuthorizationToken(
            input: input,
            messageRandomizer: token.messageRandomizer,
            signature: try .init(rawRepresentation: alteredSignature)
        )
        #expect(!signatureSubstitution.verify(using: verificationKey))
    }

    @Test("Complete the fixed 23-authorization contributor batch")
    func completeContributorAuthorizationBatch() throws {
        let evaluator = try OpalFusion.Mosaic.OpalV0.AuthorizationEvaluator
            .generate()
        let verificationKey = try #require(evaluator.verificationKey)
        var spentIdentifiers: Set<[UInt8]> = []

        for slot in 0 ..< 23 {
            let input = try authorizationInput(
                verificationKey: verificationKey,
                nonceByte: UInt8(slot)
            )
            let request = try OpalFusion.Mosaic.OpalV0.AuthorizationRequest(
                input: input,
                using: verificationKey
            )
            let token = try request.finalize(
                evaluator.evaluate(request.blindedMessage)
            )
            #expect(token.verify(using: verificationKey))
            spentIdentifiers.insert(token.spentIdentifier)
        }

        #expect(spentIdentifiers.count == 23)
    }

    @Test("Derive replay identity from token input rather than randomized signature")
    func deriveReplayIdentityFromTokenInput() throws {
        let input = try OpalFusion.Mosaic.OpalV0.AuthorizationTokenInput(
            roundIdentifier: Array(repeating: 0x21, count: 32),
            keyIdentifier: Array(repeating: 0x22, count: 32),
            nonce: Array(repeating: 0x23, count: 32)
        )
        let tokenA = OpalFusion.Mosaic.OpalV0.AuthorizationToken(
            input: input,
            messageRandomizer: try .init(
                rawRepresentation: Data(repeating: 0x31, count: 32)
            ),
            signature: try .init(rawRepresentation: Data(repeating: 0x41, count: 256))
        )
        let tokenB = OpalFusion.Mosaic.OpalV0.AuthorizationToken(
            input: input,
            messageRandomizer: try .init(
                rawRepresentation: Data(repeating: 0x32, count: 32)
            ),
            signature: try .init(rawRepresentation: Data(repeating: 0x42, count: 256))
        )

        #expect(input.canonicalBytes.contains(0x21))
        #expect(input.spentIdentifier.count == 32)
        #expect(tokenA.spentIdentifier == tokenB.spentIdentifier)
    }

    @Test("Reject malformed token input identities")
    func rejectMalformedTokenInputIdentities() {
        #expect(
            throws: OpalFusion.Mosaic.OpalV0.AuthorizationTokenInput.ValidationError
                .invalidRoundIdentifierLength(actual: 31)
        ) {
            _ = try OpalFusion.Mosaic.OpalV0.AuthorizationTokenInput(
                roundIdentifier: Array(repeating: 0, count: 31),
                keyIdentifier: Array(repeating: 0, count: 32),
                nonce: Array(repeating: 0, count: 32)
            )
        }
        #expect(
            throws: OpalFusion.Mosaic.OpalV0.AuthorizationTokenInput.ValidationError
                .invalidKeyIdentifierLength(actual: 33)
        ) {
            _ = try OpalFusion.Mosaic.OpalV0.AuthorizationTokenInput(
                roundIdentifier: Array(repeating: 0, count: 32),
                keyIdentifier: Array(repeating: 0, count: 33),
                nonce: Array(repeating: 0, count: 32)
            )
        }
        #expect(
            throws: OpalFusion.Mosaic.OpalV0.AuthorizationTokenInput.ValidationError
                .invalidNonceLength(actual: 0)
        ) {
            _ = try OpalFusion.Mosaic.OpalV0.AuthorizationTokenInput(
                roundIdentifier: Array(repeating: 0, count: 32),
                keyIdentifier: Array(repeating: 0, count: 32),
                nonce: []
            )
        }
    }

    private func makeRoster() throws -> Attempt.Roster {
        try .init(
            members: (0 ..< 7).map { index in
                .init(
                    controlIdentity: .init(validatedBytes: [UInt8(index + 1)]),
                    role: index == 0 ? .conductor : .contributor
                )
            }
        )
    }

    private func authorizationInput(
        verificationKey: OpalCrypto.RSABSSA.VerificationKey,
        nonceByte: UInt8
    ) throws -> OpalFusion.Mosaic.OpalV0.AuthorizationTokenInput {
        try .init(
            roundIdentifier: Array(repeating: 0x21, count: 32),
            keyIdentifier: [UInt8](verificationKey.keyIdentifier),
            nonce: Array(repeating: nonceByte, count: 32)
        )
    }

    private func submitRemainingRequests(
        to ledger: inout Ledger,
        roster: Attempt.Roster,
        skippingFirst: Bool = false
    ) throws -> [Ledger.Effect] {
        var lastEffects: [Ledger.Effect] = []
        for (contributorIndex, contributor) in roster.contributors.enumerated() {
            for slot in 0 ..< 23 {
                if skippingFirst, contributorIndex == 0, slot == 0 {
                    continue
                }
                lastEffects = ledger.apply(
                    input: .request(
                        contributor: contributor,
                        slot: slot,
                        blindedMessage: try blindedMessage(
                            UInt8(truncatingIfNeeded: contributorIndex * 23 + slot + 1)
                        )
                    )
                )
                if contributorIndex != roster.contributors.count - 1 || slot != 22 {
                    #expect(lastEffects.isEmpty)
                }
            }
        }
        return lastEffects
    }

    private func evaluation(from effect: Ledger.Effect) throws -> Ledger.Evaluation {
        guard case let .evaluate(evaluation) = effect else {
            throw AuthorizationFixtureError.expectedEvaluation
        }
        return evaluation
    }

    private func blindedMessage(_ byte: UInt8) throws -> OpalCrypto.RSABSSA.BlindedMessage {
        try .init(rawRepresentation: Data(repeating: byte, count: 256))
    }

    private func blindSignature(_ byte: UInt8) throws -> OpalCrypto.RSABSSA.BlindSignature {
        try .init(rawRepresentation: Data(repeating: byte, count: 256))
    }

    private enum AuthorizationFixtureError: Error {
        case expectedEvaluation
    }
}
