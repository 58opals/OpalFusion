// OpalFusion+Mosaic+OpalV0+AuthorizationEvaluator.swift

import OpalCrypto

extension OpalFusion.Mosaic.OpalV0 {
    /// The narrow boundary for a future vetted RSABSSA implementation.
    struct AuthorizationEvaluator: Sendable {
        enum Failure: Error, Sendable, Equatable {
            case unavailable
        }

        private let operation: @Sendable (
            OpalCrypto.RSABSSA.BlindedMessage
        ) throws -> OpalCrypto.RSABSSA.BlindSignature

        init(
            operation: @escaping @Sendable (
                OpalCrypto.RSABSSA.BlindedMessage
            ) throws -> OpalCrypto.RSABSSA.BlindSignature
        ) {
            self.operation = operation
        }

        func evaluate(
            _ blindedMessage: OpalCrypto.RSABSSA.BlindedMessage
        ) throws -> OpalCrypto.RSABSSA.BlindSignature {
            try operation(blindedMessage)
        }

        static let unavailable = Self { _ in
            throw Failure.unavailable
        }
    }
}
