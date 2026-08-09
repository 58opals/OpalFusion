// OpalFusion+Mosaic+OpalMainnetAlpha+AuthorizationResponseSet.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// One contributor's complete, slot-addressed blind-signature response set.
    struct AuthorizationResponseSet: Sendable, Equatable {
        let roundIdentifier: [UInt8]
        let contributor: OpalFusion.Mosaic.Attempt.ControlIdentity
        let playerCommitDigest: [UInt8]
        let responses: [OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload]
        let canonicalBytes: [UInt8]
        let digest: [UInt8]

        init(
            roundIdentifier: [UInt8],
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            playerCommitDigest: [UInt8],
            responses: [OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload]
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

            let canonicalBytes = try CanonicalWireCodec
                .encodeAuthorizationResponseSet(
                    roundIdentifier: roundIdentifier,
                    contributor: contributor,
                    playerCommitDigest: playerCommitDigest,
                    responses: responses
                )
            self.roundIdentifier = Array(roundIdentifier)
            self.contributor = contributor
            self.playerCommitDigest = Array(playerCommitDigest)
            self.responses = responses
            self.canonicalBytes = canonicalBytes
            self.digest = RoleSeedValidator.hash(
                domainSuffix: "authorization-response-set",
                fields: [canonicalBytes]
            )
        }

        init(
            playerCommit: PlayerCommit,
            issuingFrom ledger: OpalFusion.Mosaic.OpalV0
                .AuthorizationIssuanceLedger
        ) throws {
            try self.init(
                roundIdentifier: playerCommit.roundIdentifier,
                contributor: playerCommit.contributor,
                playerCommitDigest: playerCommit.digest,
                responses: try ledger.issuedResponses(
                    for: playerCommit.contributor,
                    matching: playerCommit.authorizationRequests
                )
            )
        }
    }

    /// Contributor-local proof that all responses match the retained blind requests,
    /// the manifest key, and distinct one-time authorization identities.
    struct AuthorizationResponseSetValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case responseSetMismatch
            case requestCountMismatch(actual: Int)
            case requestMismatch(slot: Int)
            case verificationKeyMismatch(slot: Int)
            case responseFinalizationFailed(slot: Int)
            case duplicateAuthorizationSpentIdentifier(slot: Int)
        }

        let responseSet: AuthorizationResponseSet
        let verificationKeyIdentifier: [UInt8]
        let authorizationTokens: [OpalFusion.Mosaic.OpalV0.AuthorizationToken]

        init(
            validating responseSet: AuthorizationResponseSet,
            playerCommit: PlayerCommit,
            requests: [OpalFusion.Mosaic.OpalV0.AuthorizationRequest],
            blindSigningVerificationKey: OpalCrypto.RSABSSA.VerificationKey
        ) throws(ValidationError) {
            guard responseSet.roundIdentifier == playerCommit.roundIdentifier,
                  responseSet.contributor == playerCommit.contributor,
                  responseSet.playerCommitDigest == playerCommit.digest else {
                throw .responseSetMismatch
            }
            guard requests.count == componentCountPerContributor else {
                throw .requestCountMismatch(actual: requests.count)
            }

            var tokens: [OpalFusion.Mosaic.OpalV0.AuthorizationToken] = []
            tokens.reserveCapacity(componentCountPerContributor)
            var spentIdentifiers: Set<[UInt8]> = []
            spentIdentifiers.reserveCapacity(componentCountPerContributor)
            for slot in 0 ..< componentCountPerContributor {
                let request = requests[slot]
                guard request.input.profile == .opalMainnetAlpha,
                      request.input.roundIdentifier
                        == responseSet.roundIdentifier,
                      request.blindedMessage
                        == playerCommit.authorizationRequests[slot].blindedMessage,
                      playerCommit.authorizationRequests[slot].slot == slot,
                      responseSet.responses[slot].slot == slot else {
                    throw .requestMismatch(slot: slot)
                }
                guard Data(request.input.keyIdentifier)
                    == blindSigningVerificationKey.keyIdentifier else {
                    throw .verificationKeyMismatch(slot: slot)
                }
                let token: OpalFusion.Mosaic.OpalV0.AuthorizationToken
                do {
                    token = try request.finalize(
                        responseSet.responses[slot].blindSignature
                    )
                } catch {
                    throw .responseFinalizationFailed(slot: slot)
                }
                let insertion = spentIdentifiers.insert(token.spentIdentifier)
                guard insertion.inserted else {
                    throw .duplicateAuthorizationSpentIdentifier(slot: slot)
                }
                tokens.append(token)
            }
            self.responseSet = responseSet
            self.verificationKeyIdentifier = [UInt8](
                blindSigningVerificationKey.keyIdentifier
            )
            self.authorizationTokens = tokens
        }
    }
}
