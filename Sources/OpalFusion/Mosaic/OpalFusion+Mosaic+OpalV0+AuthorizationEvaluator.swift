// OpalFusion+Mosaic+OpalV0+AuthorizationEvaluator.swift

import OpalCrypto

extension OpalFusion.Mosaic.OpalV0 {
    /// Attempt-scoped evaluation of blinded component authorizations.
    enum AuthorizationEvaluator: Sendable {
        enum Failure: Error, Sendable, Equatable {
            case unavailable
        }

        case active(OpalCrypto.RSABSSA.SigningKey)
        case unavailable

        /// Generates a fresh evaluator for exactly one Mosaic attempt.
        static func generate() throws -> Self {
            .active(try OpalCrypto.RSABSSA.SigningKey.generate())
        }

        /// The verification key that must be committed by the attempt manifest.
        var verificationKey: OpalCrypto.RSABSSA.VerificationKey? {
            switch self {
            case let .active(signingKey):
                signingKey.verificationKey
            case .unavailable:
                nil
            }
        }

        func evaluate(
            _ blindedMessage: OpalCrypto.RSABSSA.BlindedMessage
        ) throws -> OpalCrypto.RSABSSA.BlindSignature {
            switch self {
            case let .active(signingKey):
                try signingKey.blindSign(blindedMessage)
            case .unavailable:
                throw Failure.unavailable
            }
        }
    }
}
