// OpalFusion+Mosaic+OpalV0+AuthorizationRequest.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalV0 {
    /// Contributor-local state for one blinded component authorization.
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
            guard Data(input.keyIdentifier)
                == verificationKey.keyIdentifier else {
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

        /// Finalizes and verifies the evaluator response before constructing a token.
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
