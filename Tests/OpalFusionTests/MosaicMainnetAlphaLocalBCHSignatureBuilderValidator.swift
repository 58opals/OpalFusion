// MosaicMainnetAlphaLocalBCHSignatureBuilderValidator.swift

import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha local BCH signature builder")
struct MosaicMainnetAlphaLocalBCHSignatureBuilderValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Fixture = MosaicMainnetAlphaExecutionFixtures

    enum FinalizedSubstitution: CaseIterable, Sendable {
        case localInputUnsigned
        case nonLocalInputSigned
        case invalidLocalSignature
    }

    @Test("Bind host-produced local signatures to retained slots and tokens")
    func bindLocalSignatures() async throws {
        let prepared = try await Fixture.prepare()
        let publications = try Alpha.LocalBCHSignatureBuilder.build(
            finalizedTransaction: prepared.localFinalizedTransaction,
            signingRequest: prepared.signingRequest,
            transcript: prepared.materialized.prepared.transcript,
            material: prepared.localMaterial,
            authorizationValidation: prepared.localAuthorizationValidation
        )
        let inputIndex = try #require(
            prepared.signingRequest.localInputIndices.first
        )
        let localInput = prepared.signingRequest.spentInputs[inputIndex]
        let materialSlot = try #require(
            prepared.localMaterial.slots.first { slot in
                guard case let .input(input) = slot.component.payload else {
                    return false
                }
                return input.previousTransactionHash
                        == localInput.outpointTransactionHashBytes
                    && input.outputIndex == localInput.outpointIndex
            }
        )
        let publication = try #require(publications.first)

        #expect(publications.count == 1)
        #expect(publication.slot == materialSlot.slot)
        #expect(
            publication.recipientEventIdentity
                == materialSlot.recipientEventIdentity
        )
        #expect(
            publication.submission.authorizationToken
                == prepared.localAuthorizationValidation
                    .bchSignatureAuthorizationTokens[materialSlot.slot]
        )
        #expect(
            publication.submission.entry
                == prepared.signatureSet.entries[inputIndex]
        )
    }

    @Test("Reject host output outside the exact local signing authority")
    func rejectFinalizedSubstitution() async throws {
        let prepared = try await Fixture.prepare()
        let transcript = prepared.materialized.prepared.transcript
        let localIndex = try #require(
            prepared.signingRequest.localInputIndices.first
        )
        let nonLocalIndex = try #require(
            transcript.transaction.inputs.indices.first {
                !prepared.signingRequest.localInputIndices.contains($0)
            }
        )
        for substitution in FinalizedSubstitution.allCases {
            var transaction = try OpalFusion.Execution.BCHTransaction.parse(
                prepared.localFinalizedTransaction.signedFusionTransactionBytes
            )
            let expectedFailure: Alpha.LocalBCHSignatureBuilder.Failure

            switch substitution {
            case .localInputUnsigned:
                transaction = try transaction.settingUnlockingScript(
                    [],
                    at: localIndex
                )
                expectedFailure = .localInputUnsigned(index: localIndex)
            case .nonLocalInputSigned:
                transaction = try transaction.settingUnlockingScript(
                    Fixture.unlockingScript(
                        for: prepared.signatureSet.entries[nonLocalIndex]
                    ),
                    at: nonLocalIndex
                )
                expectedFailure = .nonLocalInputSigned(index: nonLocalIndex)
            case .invalidLocalSignature:
                var unlockingScript = transaction.inputs[localIndex]
                    .unlockingScript
                unlockingScript[1] ^= 0x01
                transaction = try transaction.settingUnlockingScript(
                    unlockingScript,
                    at: localIndex
                )
                expectedFailure = .signatureInvalid(index: localIndex)
            }

            #expect(throws: expectedFailure, "Substitution: \(substitution)") {
                _ = try Alpha.LocalBCHSignatureBuilder.build(
                    finalizedTransaction: .init(
                        signedFusionTransactionBytes: try transaction.serialize()
                    ),
                    signingRequest: prepared.signingRequest,
                    transcript: transcript,
                    material: prepared.localMaterial,
                    authorizationValidation:
                        prepared.localAuthorizationValidation
                )
            }
        }
    }
}
