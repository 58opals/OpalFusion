// OpalFusion+Mosaic+OpalV0+AuthorizationEvaluator.swift

@_spi(MosaicPrivateAlpha) import OpalCrypto
import Security

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

        /// Restores one exact attempt key without export or regeneration.
        static func restore(
            securityKey: SecKey,
            expectedVerificationKey: OpalCrypto.RSABSSA.VerificationKey
        ) throws -> Self {
            .active(
                try OpalCrypto.RSABSSA.SigningKey(
                    restoring: securityKey,
                    matching: expectedVerificationKey
                )
            )
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
