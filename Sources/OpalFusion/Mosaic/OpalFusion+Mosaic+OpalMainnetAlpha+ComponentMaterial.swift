// OpalFusion+Mosaic+OpalMainnetAlpha+ComponentMaterial.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    enum ComponentHashing {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidRoundIdentifierLength(actual: Int)
            case invalidSaltLength(actual: Int)
        }

        static func saltCommitment(
            roundIdentifier: [UInt8],
            salt: [UInt8]
        ) throws -> [UInt8] {
            try validate(roundIdentifier: roundIdentifier, salt: salt)
            return RoleSeedValidator.hash(
                domainSuffix: "component-salt",
                fields: [roundIdentifier, salt]
            )
        }

        static func saltedComponentDigest(
            roundIdentifier: [UInt8],
            salt: [UInt8],
            payload: OpalFusion.Mosaic.OpalV0.ComponentPayload
        ) throws -> [UInt8] {
            try validate(roundIdentifier: roundIdentifier, salt: salt)
            return RoleSeedValidator.hash(
                domainSuffix: "salted-component",
                fields: [
                    roundIdentifier,
                    salt,
                    try OpalFusion.Mosaic.OpalV0.CanonicalWireCodec
                        .encodeComponentPayload(payload)
                ]
            )
        }

        private static func validate(
            roundIdentifier: [UInt8],
            salt: [UInt8]
        ) throws {
            guard roundIdentifier.count == 32 else {
                throw ValidationError.invalidRoundIdentifierLength(
                    actual: roundIdentifier.count
                )
            }
            guard salt.count == 32 else {
                throw ValidationError.invalidSaltLength(actual: salt.count)
            }
        }
    }

    struct ComponentSlotSecrets: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidSaltLength(actual: Int)
            case invalidComponentAuthorizationNonceLength(actual: Int)
            case invalidBCHSignatureAuthorizationNonceLength(actual: Int)
            case invalidRecipientEventIdentity
        }

        let salt: [UInt8]
        let pedersenNonce: OpalCrypto.Pedersen.Nonce
        let communicationPrivateKey: OpalCrypto.Secp256k1.PrivateKey
        let componentAuthorizationNonce: [UInt8]
        let bchSignatureAuthorizationNonce: [UInt8]
        let recipientEventIdentity: [UInt8]

        init(
            salt: [UInt8],
            pedersenNonce: OpalCrypto.Pedersen.Nonce,
            communicationPrivateKey: OpalCrypto.Secp256k1.PrivateKey,
            componentAuthorizationNonce: [UInt8],
            bchSignatureAuthorizationNonce: [UInt8],
            recipientEventIdentity: [UInt8]
        ) throws {
            guard salt.count == 32 else {
                throw ValidationError.invalidSaltLength(actual: salt.count)
            }
            guard componentAuthorizationNonce.count == 32 else {
                throw ValidationError.invalidComponentAuthorizationNonceLength(
                    actual: componentAuthorizationNonce.count
                )
            }
            guard bchSignatureAuthorizationNonce.count == 32 else {
                throw ValidationError.invalidBCHSignatureAuthorizationNonceLength(
                    actual: bchSignatureAuthorizationNonce.count
                )
            }
            do {
                _ = try OpalCrypto.Signature.BIP340.VerificationKey(
                    rawRepresentation: Data(recipientEventIdentity)
                )
            } catch {
                throw ValidationError.invalidRecipientEventIdentity
            }
            self.salt = Array(salt)
            self.pedersenNonce = pedersenNonce
            self.communicationPrivateKey = communicationPrivateKey
            self.componentAuthorizationNonce = Array(
                componentAuthorizationNonce
            )
            self.bchSignatureAuthorizationNonce = Array(
                bchSignatureAuthorizationNonce
            )
            self.recipientEventIdentity = Array(recipientEventIdentity)
        }

    }

    struct ComponentSlotMaterial: Sendable {
        let slot: Int
        let component: OpalFusion.Mosaic.OpalV0.Component
        let salt: [UInt8]
        let contributionSatoshis: Int64
        let pedersenNonce: OpalCrypto.Pedersen.Nonce
        let commitment: OpalFusion.Mosaic.OpalV0.ComponentCommitment
        let communicationPrivateKey: OpalCrypto.Secp256k1.PrivateKey
        let recipientEventIdentity: [UInt8]
        let componentAuthorizationRequest: AuthorizationRequest
        let bchSignatureAuthorizationRequest: AuthorizationRequest
    }
}
