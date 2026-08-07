// OpalFusion+Mosaic+OpalV0+AuthorizationWirePayload.swift

import OpalCrypto

extension OpalFusion.Mosaic.OpalV0 {
    struct AuthorizationRequestPayload: Sendable, Equatable {
        let slot: Int
        let blindedMessage: OpalCrypto.RSABSSA.BlindedMessage

        init(
            slot: Int,
            blindedMessage: OpalCrypto.RSABSSA.BlindedMessage
        ) throws {
            try Self.validate(slot: slot)
            self.slot = slot
            self.blindedMessage = blindedMessage
        }

        private static func validate(slot: Int) throws {
            guard (0 ..< OpalFusion.Mosaic.OpalV0.componentAuthorizationCountPerContributor)
                .contains(slot) else {
                throw WireContractError.invalidAuthorizationSlot(actual: slot)
            }
        }
    }

    struct AuthorizationResponsePayload: Sendable, Equatable {
        let slot: Int
        let blindSignature: OpalCrypto.RSABSSA.BlindSignature

        init(
            slot: Int,
            blindSignature: OpalCrypto.RSABSSA.BlindSignature
        ) throws {
            guard (0 ..< OpalFusion.Mosaic.OpalV0.componentAuthorizationCountPerContributor)
                .contains(slot) else {
                throw WireContractError.invalidAuthorizationSlot(actual: slot)
            }
            self.slot = slot
            self.blindSignature = blindSignature
        }
    }
}
