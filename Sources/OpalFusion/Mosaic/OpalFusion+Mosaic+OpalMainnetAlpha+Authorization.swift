// OpalFusion+Mosaic+OpalMainnetAlpha+Authorization.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    enum AuthorizationPurpose: UInt8, Sendable, CaseIterable {
        case component = 0
        case bchSignature = 1
    }

    struct AuthorizationTokenInput: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidRoundIdentifierLength(actual: Int)
            case invalidKeyIdentifierLength(actual: Int)
            case invalidNonceLength(actual: Int)
            case invalidBindingLength(actual: Int)
        }

        let roundIdentifier: [UInt8]
        let keyIdentifier: [UInt8]
        let purpose: AuthorizationPurpose
        let nonce: [UInt8]
        let binding: [UInt8]
        let canonicalBytes: [UInt8]
        let spentIdentifier: [UInt8]

        init(
            roundIdentifier: [UInt8],
            keyIdentifier: [UInt8],
            purpose: AuthorizationPurpose,
            nonce: [UInt8],
            binding: [UInt8]
        ) throws {
            guard roundIdentifier.count == OpalFusion.Mosaic.OpalV0.digestByteCount else {
                throw ValidationError.invalidRoundIdentifierLength(
                    actual: roundIdentifier.count
                )
            }
            guard keyIdentifier.count == OpalFusion.Mosaic.OpalV0.digestByteCount else {
                throw ValidationError.invalidKeyIdentifierLength(
                    actual: keyIdentifier.count
                )
            }
            guard nonce.count == OpalFusion.Mosaic.OpalV0.digestByteCount else {
                throw ValidationError.invalidNonceLength(actual: nonce.count)
            }
            guard binding.count == OpalFusion.Mosaic.OpalV0.digestByteCount else {
                throw ValidationError.invalidBindingLength(actual: binding.count)
            }

            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            try encoder.writeText(
                "\(OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue)/authorization/input"
            )
            try encoder.writeBytes(OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash)
            try encoder.writeBytes(roundIdentifier)
            try encoder.writeBytes(keyIdentifier)
            encoder.writeUInt8(purpose.rawValue)
            try encoder.writeBytes(nonce)
            try encoder.writeBytes(binding)
            let canonicalBytes = encoder.encodedBytes

            self.roundIdentifier = Array(roundIdentifier)
            self.keyIdentifier = Array(keyIdentifier)
            self.purpose = purpose
            self.nonce = Array(nonce)
            self.binding = Array(binding)
            self.canonicalBytes = canonicalBytes
            self.spentIdentifier = RoleSeedValidator.hash(
                domainSuffix: "authorization-spent",
                fields: [canonicalBytes]
            )
        }

        static func componentBinding(
            for component: OpalFusion.Mosaic.OpalV0.Component
        ) throws -> [UInt8] {
            RoleSeedValidator.hash(
                domainSuffix: "component-authorization/payload",
                fields: [
                    try OpalFusion.Mosaic.OpalV0.CanonicalWireCodec
                        .encodeComponent(component)
                ]
            )
        }
    }

    struct AuthorizationToken: Sendable, Equatable {
        let input: AuthorizationTokenInput
        let messageRandomizer: OpalCrypto.RSABSSA.MessageRandomizer
        let signature: OpalCrypto.RSABSSA.Signature

        var spentIdentifier: [UInt8] {
            input.spentIdentifier
        }

        func verify(
            purpose: AuthorizationPurpose,
            binding: [UInt8],
            using verificationKey: OpalCrypto.RSABSSA.VerificationKey
        ) -> Bool {
            guard input.purpose == purpose,
                  input.binding == binding,
                  Data(input.keyIdentifier) == verificationKey.keyIdentifier else {
                return false
            }
            return signature.verify(
                message: Data(input.canonicalBytes),
                messageRandomizer: messageRandomizer,
                using: verificationKey
            )
        }
    }

    /// Contributor-local state for one purpose- and payload-bound blind authorization.
    struct AuthorizationRequest: Sendable {
        enum Failure: Error, Sendable, Equatable {
            case verificationKeyIdentifierMismatch
        }

        let input: AuthorizationTokenInput
        let blindedMessage: OpalCrypto.RSABSSA.BlindedMessage

        private let blindRequest: OpalCrypto.RSABSSA.BlindRequest
        private let verificationKey: OpalCrypto.RSABSSA.VerificationKey

        init(
            input: AuthorizationTokenInput,
            using verificationKey: OpalCrypto.RSABSSA.VerificationKey
        ) throws {
            guard Data(input.keyIdentifier) == verificationKey.keyIdentifier else {
                throw Failure.verificationKeyIdentifierMismatch
            }
            let blindRequest = try OpalCrypto.RSABSSA.makeBlindRequest(
                message: Data(input.canonicalBytes),
                using: verificationKey
            )
            self.input = input
            self.blindedMessage = blindRequest.blindedMessage
            self.blindRequest = blindRequest
            self.verificationKey = verificationKey
        }

        func finalize(
            _ blindSignature: OpalCrypto.RSABSSA.BlindSignature
        ) throws -> AuthorizationToken {
            AuthorizationToken(
                input: input,
                messageRandomizer: blindRequest.messageRandomizer,
                signature: try blindRequest.finalize(
                    blindSignature,
                    using: verificationKey
                )
            )
        }
    }
}
