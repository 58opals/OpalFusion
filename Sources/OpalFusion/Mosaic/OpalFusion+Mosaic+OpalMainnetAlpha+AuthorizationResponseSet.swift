// OpalFusion+Mosaic+OpalMainnetAlpha+AuthorizationResponseSet.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// One contributor's complete, slot-addressed blind-signature response set.
    struct AuthorizationResponseSet: Sendable, Equatable {
        let roundIdentifier: [UInt8]
        let contributor: OpalFusion.Mosaic.Attempt.ControlIdentity
        let playerCommitDigest: [UInt8]
        let componentAuthorizationResponses: [
            OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload
        ]
        let bchSignatureAuthorizationResponses: [
            OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload
        ]
        let canonicalBytes: [UInt8]
        let digest: [UInt8]

        init(
            roundIdentifier: [UInt8],
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            playerCommitDigest: [UInt8],
            componentAuthorizationResponses: [
                OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload
            ],
            bchSignatureAuthorizationResponses: [
                OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload
            ]
        ) throws {
            try RoleSeedValidator.validateFixed(
                roundIdentifier,
                field: .roundIdentifier
            )
            try RoleSeedValidator.validateFixed(
                contributor.validatedBytes,
                field: .controlIdentity
            )
            do {
                _ = try OpalCrypto.Signature.BIP340.VerificationKey(
                    rawRepresentation: Data(contributor.validatedBytes)
                )
            } catch {
                throw ContractError.invalidControlIdentity
            }
            try RoleSeedValidator.validateFixed(
                playerCommitDigest,
                field: .playerCommitDigest
            )
            try Self.validateAuthorizationResponses(
                componentAuthorizationResponses
            )
            try Self.validateAuthorizationResponses(
                bchSignatureAuthorizationResponses
            )

            let canonicalBytes = try CanonicalWireCodec
                .encodeAuthorizationResponseSet(
                    roundIdentifier: roundIdentifier,
                    contributor: contributor,
                    playerCommitDigest: playerCommitDigest,
                    componentAuthorizationResponses:
                        componentAuthorizationResponses,
                    bchSignatureAuthorizationResponses:
                        bchSignatureAuthorizationResponses
                )
            self.roundIdentifier = Array(roundIdentifier)
            self.contributor = contributor
            self.playerCommitDigest = Array(playerCommitDigest)
            self.componentAuthorizationResponses =
                componentAuthorizationResponses
            self.bchSignatureAuthorizationResponses =
                bchSignatureAuthorizationResponses
            self.canonicalBytes = canonicalBytes
            self.digest = RoleSeedValidator.hash(
                domainSuffix: "authorization-response-set",
                fields: [canonicalBytes]
            )
        }

        init(
            playerCommit: PlayerCommit,
            componentIssuingFrom componentLedger: OpalFusion.Mosaic.OpalV0
                .AuthorizationIssuanceLedger,
            bchSignatureIssuingFrom bchSignatureLedger: OpalFusion.Mosaic.OpalV0
                .AuthorizationIssuanceLedger
        ) throws {
            try self.init(
                roundIdentifier: playerCommit.roundIdentifier,
                contributor: playerCommit.contributor,
                playerCommitDigest: playerCommit.digest,
                componentAuthorizationResponses: try componentLedger.issuedResponses(
                    for: playerCommit.contributor,
                    matching: playerCommit.componentAuthorizationRequests
                ),
                bchSignatureAuthorizationResponses: try bchSignatureLedger
                    .issuedResponses(
                        for: playerCommit.contributor,
                        matching: playerCommit.bchSignatureAuthorizationRequests
                    )
            )
        }

        private static func validateAuthorizationResponses(
            _ responses: [OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload]
        ) throws {
            guard responses.count == componentCountPerContributor else {
                throw ContractError.invalidAuthorizationResponseCount(
                    actual: responses.count
                )
            }
            for (expectedSlot, response) in responses.enumerated() {
                guard response.slot == expectedSlot else {
                    throw ContractError.invalidAuthorizationResponseSlot(
                        expected: expectedSlot,
                        actual: response.slot
                    )
                }
            }
        }
    }

    /// Contributor-local proof that all responses match the retained blind requests,
    /// the manifest key, and distinct one-time authorization identities.
    struct AuthorizationResponseSetValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case responseSetMismatch
            case requestCountMismatch(actual: Int)
            case componentCountMismatch(actual: Int)
            case componentBindingMismatch(slot: Int)
            case bchSignatureBindingMismatch(slot: Int)
            case requestMismatch(purpose: AuthorizationPurpose, slot: Int)
            case verificationKeyMismatch(purpose: AuthorizationPurpose, slot: Int)
            case responseFinalizationFailed(purpose: AuthorizationPurpose, slot: Int)
            case duplicateAuthorizationSpentIdentifier(
                purpose: AuthorizationPurpose,
                slot: Int
            )
        }

        let responseSet: AuthorizationResponseSet
        let componentVerificationKeyIdentifier: [UInt8]
        let bchSignatureVerificationKeyIdentifier: [UInt8]
        let componentAuthorizationTokens: [AuthorizationToken]
        let bchSignatureAuthorizationTokens: [AuthorizationToken]

        init(
            validating responseSet: AuthorizationResponseSet,
            playerCommit: PlayerCommit,
            componentRequests: [AuthorizationRequest],
            bchSignatureRequests: [AuthorizationRequest],
            components: [OpalFusion.Mosaic.OpalV0.Component],
            componentAuthorizationVerificationKey:
                OpalCrypto.RSABSSA.VerificationKey,
            bchSignatureAuthorizationVerificationKey:
                OpalCrypto.RSABSSA.VerificationKey
        ) throws(ValidationError) {
            guard responseSet.roundIdentifier == playerCommit.roundIdentifier,
                  responseSet.contributor == playerCommit.contributor,
                  responseSet.playerCommitDigest == playerCommit.digest else {
                throw .responseSetMismatch
            }
            guard componentRequests.count == componentCountPerContributor else {
                throw .requestCountMismatch(actual: componentRequests.count)
            }
            guard bchSignatureRequests.count == componentCountPerContributor else {
                throw .requestCountMismatch(actual: bchSignatureRequests.count)
            }
            guard components.count == componentCountPerContributor else {
                throw .componentCountMismatch(actual: components.count)
            }
            for slot in 0 ..< componentCountPerContributor {
                let expectedComponentBinding: [UInt8]
                do {
                    expectedComponentBinding = try AuthorizationTokenInput
                        .componentBinding(for: components[slot])
                } catch {
                    throw .componentBindingMismatch(slot: slot)
                }
                guard componentRequests[slot].input.binding
                    == expectedComponentBinding else {
                    throw .componentBindingMismatch(slot: slot)
                }
                guard bchSignatureRequests[slot].input.binding
                    == componentRequests[slot].input.spentIdentifier else {
                    throw .bchSignatureBindingMismatch(slot: slot)
                }
            }
            let componentTokens = try Self.finalize(
                purpose: .component,
                requests: componentRequests,
                requestPayloads: playerCommit.componentAuthorizationRequests,
                responses: responseSet.componentAuthorizationResponses,
                roundIdentifier: responseSet.roundIdentifier,
                verificationKey: componentAuthorizationVerificationKey
            )
            let bchSignatureTokens = try Self.finalize(
                purpose: .bchSignature,
                requests: bchSignatureRequests,
                requestPayloads: playerCommit.bchSignatureAuthorizationRequests,
                responses: responseSet.bchSignatureAuthorizationResponses,
                roundIdentifier: responseSet.roundIdentifier,
                verificationKey: bchSignatureAuthorizationVerificationKey
            )
            self.responseSet = responseSet
            self.componentVerificationKeyIdentifier = [UInt8](
                componentAuthorizationVerificationKey.keyIdentifier
            )
            self.bchSignatureVerificationKeyIdentifier = [UInt8](
                bchSignatureAuthorizationVerificationKey.keyIdentifier
            )
            self.componentAuthorizationTokens = componentTokens
            self.bchSignatureAuthorizationTokens = bchSignatureTokens
        }

        private static func finalize(
            purpose: AuthorizationPurpose,
            requests: [AuthorizationRequest],
            requestPayloads: [OpalFusion.Mosaic.OpalV0.AuthorizationRequestPayload],
            responses: [OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload],
            roundIdentifier: [UInt8],
            verificationKey: OpalCrypto.RSABSSA.VerificationKey
        ) throws(ValidationError) -> [AuthorizationToken] {
            var tokens: [AuthorizationToken] = []
            tokens.reserveCapacity(componentCountPerContributor)
            var spentIdentifiers: Set<[UInt8]> = []
            spentIdentifiers.reserveCapacity(componentCountPerContributor)
            for slot in 0 ..< componentCountPerContributor {
                let request = requests[slot]
                guard request.input.purpose == purpose,
                      request.input.roundIdentifier == roundIdentifier,
                      request.blindedMessage == requestPayloads[slot].blindedMessage,
                      requestPayloads[slot].slot == slot,
                      responses[slot].slot == slot else {
                    throw .requestMismatch(purpose: purpose, slot: slot)
                }
                guard Data(request.input.keyIdentifier)
                    == verificationKey.keyIdentifier else {
                    throw .verificationKeyMismatch(purpose: purpose, slot: slot)
                }
                let token: AuthorizationToken
                do {
                    token = try request.finalize(responses[slot].blindSignature)
                } catch {
                    throw .responseFinalizationFailed(
                        purpose: purpose,
                        slot: slot
                    )
                }
                guard spentIdentifiers.insert(token.spentIdentifier).inserted else {
                    throw .duplicateAuthorizationSpentIdentifier(
                        purpose: purpose,
                        slot: slot
                    )
                }
                tokens.append(token)
            }
            return tokens
        }
    }

    /// Binds finalized authorization responses to one validated local material owner.
    ///
    /// The contained cryptographic validation cannot be replayed under a different attempt,
    /// generation, or material identifier because this value can only be constructed from a
    /// `LocalContributionMaterial` produced by its fail-closed builder.
    struct AuthorizationResponseSetMaterialValidation: Sendable, Equatable {
        typealias AttemptIdentifier = OpalFusion.Mosaic.LocalAttempt
            .AttemptIdentifier
        typealias GenerationIdentifier = OpalFusion.Mosaic.LocalAttempt
            .GenerationIdentifier
        typealias MaterialIdentifier = OpalFusion.Mosaic.LocalAttempt
            .MaterialIdentifier

        let attemptIdentifier: AttemptIdentifier
        let generationIdentifier: GenerationIdentifier
        let materialIdentifier: MaterialIdentifier
        let responseValidation: AuthorizationResponseSetValidation

        var responseSet: AuthorizationResponseSet {
            responseValidation.responseSet
        }

        var componentVerificationKeyIdentifier: [UInt8] {
            responseValidation.componentVerificationKeyIdentifier
        }

        var bchSignatureVerificationKeyIdentifier: [UInt8] {
            responseValidation.bchSignatureVerificationKeyIdentifier
        }

        var componentAuthorizationTokens: [AuthorizationToken] {
            responseValidation.componentAuthorizationTokens
        }

        var bchSignatureAuthorizationTokens: [AuthorizationToken] {
            responseValidation.bchSignatureAuthorizationTokens
        }

        init(
            validating responseSet: AuthorizationResponseSet,
            material: LocalContributionMaterial
        ) throws(AuthorizationResponseSetValidation.ValidationError) {
            let responseValidation = try AuthorizationResponseSetValidation(
                validating: responseSet,
                playerCommit: material.playerCommit,
                componentRequests: material.slots.map {
                    $0.componentAuthorizationRequest
                },
                bchSignatureRequests: material.slots.map {
                    $0.bchSignatureAuthorizationRequest
                },
                components: material.slots.map(\.component),
                componentAuthorizationVerificationKey:
                    material.manifest.core
                        .componentAuthorizationVerificationKey,
                bchSignatureAuthorizationVerificationKey:
                    material.manifest.core
                        .bchSignatureAuthorizationVerificationKey
            )
            self.attemptIdentifier = material.attemptIdentifier
            self.generationIdentifier = material.generationIdentifier
            self.materialIdentifier = material.materialIdentifier
            self.responseValidation = responseValidation
        }
    }
}
