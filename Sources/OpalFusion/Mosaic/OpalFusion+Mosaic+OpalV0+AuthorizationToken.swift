// OpalFusion+Mosaic+OpalV0+AuthorizationToken.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalV0 {
    struct AuthorizationTokenInput: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case unsupportedProfile(OpalFusion.Mosaic.Profile)
            case invalidRoundIdentifierLength(actual: Int)
            case invalidKeyIdentifierLength(actual: Int)
            case invalidNonceLength(actual: Int)
        }

        let profile: OpalFusion.Mosaic.Profile
        let roundIdentifier: [UInt8]
        let keyIdentifier: [UInt8]
        let nonce: [UInt8]
        let canonicalBytes: [UInt8]
        let spentIdentifier: [UInt8]

        init(
            profile: OpalFusion.Mosaic.Profile = .opalV0,
            roundIdentifier: [UInt8],
            keyIdentifier: [UInt8],
            nonce: [UInt8]
        ) throws {
            guard profile.supportsExecutableCore,
                  let networkGenesisHash = profile.networkGenesisHash else {
                throw ValidationError.unsupportedProfile(profile)
            }
            guard roundIdentifier.count == 32 else {
                throw ValidationError.invalidRoundIdentifierLength(
                    actual: roundIdentifier.count
                )
            }
            guard keyIdentifier.count == 32 else {
                throw ValidationError.invalidKeyIdentifierLength(
                    actual: keyIdentifier.count
                )
            }
            guard nonce.count == 32 else {
                throw ValidationError.invalidNonceLength(actual: nonce.count)
            }
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            try encoder.writeText("\(profile.rawValue)/component-authorization/input")
            try encoder.writeBytes(networkGenesisHash)
            try encoder.writeBytes(roundIdentifier)
            try encoder.writeBytes(keyIdentifier)
            try encoder.writeBytes(nonce)
            let canonicalBytes = encoder.encodedBytes

            self.profile = profile
            self.roundIdentifier = Array(roundIdentifier)
            self.keyIdentifier = Array(keyIdentifier)
            self.nonce = Array(nonce)
            self.canonicalBytes = canonicalBytes
            self.spentIdentifier = [UInt8](
                OpalCrypto.Hashing.sha256(
                    Data("\(profile.rawValue)/component-authorization/spent".utf8)
                        + Data(canonicalBytes)
                )
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

        /// Verifies the input/key binding and randomized RSABSSA signature.
        func verify(
            using verificationKey: OpalCrypto.RSABSSA.VerificationKey
        ) -> Bool {
            guard Data(input.keyIdentifier)
                == verificationKey.keyIdentifier else {
                return false
            }
            return signature.verify(
                message: Data(input.canonicalBytes),
                messageRandomizer: messageRandomizer,
                using: verificationKey
            )
        }
    }
}
