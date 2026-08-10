// OpalFusion+Mosaic+OpalMainnetAlpha+PlayerCommit.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// One contributor's complete grouped commitment and slot-addressed blind requests.
    struct PlayerCommit: Sendable, Equatable {
        let roundIdentifier: [UInt8]
        let contributor: OpalFusion.Mosaic.Attempt.ControlIdentity
        let groupedCommitment: OpalFusion.Mosaic.OpalV0.GroupedCommitmentPayload
        let componentAuthorizationRequests: [
            OpalFusion.Mosaic.OpalV0.AuthorizationRequestPayload
        ]
        let bchSignatureAuthorizationRequests: [
            OpalFusion.Mosaic.OpalV0.AuthorizationRequestPayload
        ]
        let canonicalBytes: [UInt8]
        let digest: [UInt8]

        init(
            roundIdentifier: [UInt8],
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            groupedCommitment: OpalFusion.Mosaic.OpalV0.GroupedCommitmentPayload,
            componentAuthorizationRequests: [
                OpalFusion.Mosaic.OpalV0.AuthorizationRequestPayload
            ],
            bchSignatureAuthorizationRequests: [
                OpalFusion.Mosaic.OpalV0.AuthorizationRequestPayload
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
            guard groupedCommitment.profile == .opalMainnetAlpha else {
                throw ContractError.groupedCommitmentProfileMismatch(
                    groupedCommitment.profile
                )
            }
            try Self.validateAuthorizationRequests(componentAuthorizationRequests)
            try Self.validateAuthorizationRequests(
                bchSignatureAuthorizationRequests
            )

            let canonicalBytes = try CanonicalWireCodec.encodePlayerCommit(
                roundIdentifier: roundIdentifier,
                contributor: contributor,
                groupedCommitment: groupedCommitment,
                componentAuthorizationRequests: componentAuthorizationRequests,
                bchSignatureAuthorizationRequests:
                    bchSignatureAuthorizationRequests
            )
            self.roundIdentifier = Array(roundIdentifier)
            self.contributor = contributor
            self.groupedCommitment = groupedCommitment
            self.componentAuthorizationRequests = componentAuthorizationRequests
            self.bchSignatureAuthorizationRequests =
                bchSignatureAuthorizationRequests
            self.canonicalBytes = canonicalBytes
            self.digest = RoleSeedValidator.hash(
                domainSuffix: "player-commit",
                fields: [canonicalBytes]
            )
        }

        private static func validateAuthorizationRequests(
            _ requests: [OpalFusion.Mosaic.OpalV0.AuthorizationRequestPayload]
        ) throws {
            guard requests.count == componentCountPerContributor else {
                throw ContractError.invalidAuthorizationRequestCount(
                    actual: requests.count
                )
            }
            for (expectedSlot, request) in requests.enumerated() {
                guard request.slot == expectedSlot else {
                    throw ContractError.invalidAuthorizationRequestSlot(
                        expected: expectedSlot,
                        actual: request.slot
                    )
                }
            }
        }
    }
}
