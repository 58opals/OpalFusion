// MosaicOpalV0WireContractValidator+Authorization.swift

import Foundation
import OpalCrypto
@testable import OpalFusion
import Testing

extension MosaicOpalV0WireContractValidator {
    @Test("Authorization request and response payloads pin slot-first bytes")
    func validateAuthorizationPayloadGoldenVectors() throws {
        let request = try OpalV0.AuthorizationRequestPayload(
            slot: 7,
            blindedMessage: .init(
                rawRepresentation: Data(repeating: 0xAA, count: 256)
            )
        )
        let requestBytes = try Codec.encodeAuthorizationRequest(request)
        #expect(requestBytes == [0x07] + [UInt8](repeating: 0xAA, count: 256))
        #expect(try Codec.decodeAuthorizationRequest(from: requestBytes) == request)

        let response = try OpalV0.AuthorizationResponsePayload(
            slot: 22,
            blindSignature: .init(
                rawRepresentation: Data(repeating: 0xBB, count: 256)
            )
        )
        let responseBytes = try Codec.encodeAuthorizationResponse(response)
        #expect(responseBytes == [0x16] + [UInt8](repeating: 0xBB, count: 256))
        #expect(try Codec.decodeAuthorizationResponse(from: responseBytes) == response)
    }

    @Test("Authorization tokens match the pinned fixed-width document")
    func validateAuthorizationTokenGoldenVector() throws {
        let token = try Self.makeAuthorizationToken()
        let encoded = try Codec.encodeAuthorizationToken(token)

        #expect(encoded == Self.rawAuthorizationTokenBytes())
        #expect(encoded.count == 384)
        #expect(
            Self.sha256Hexadecimal(encoded)
                == "1afec0ff139ed7a4beab5807f88851ab1a8d2e0a371bf27ac3553f42ed787993"
        )
        #expect(try Codec.decodeAuthorizationToken(from: encoded) == token)
    }

    @Test("Authorization payloads reject slots outside 0 through 22")
    func rejectInvalidAuthorizationSlots() throws {
        let blindedMessage = try OpalCrypto.RSABSSA.BlindedMessage(
            rawRepresentation: Data(repeating: 0xAA, count: 256)
        )
        let blindSignature = try OpalCrypto.RSABSSA.BlindSignature(
            rawRepresentation: Data(repeating: 0xBB, count: 256)
        )

        #expect(throws: WireContractError.invalidAuthorizationSlot(actual: -1)) {
            _ = try OpalV0.AuthorizationRequestPayload(
                slot: -1,
                blindedMessage: blindedMessage
            )
        }
        #expect(throws: WireContractError.invalidAuthorizationSlot(actual: 23)) {
            _ = try OpalV0.AuthorizationResponsePayload(
                slot: 23,
                blindSignature: blindSignature
            )
        }
        #expect(throws: WireContractError.invalidAuthorizationSlot(actual: 23)) {
            _ = try Codec.decodeAuthorizationRequest(
                from: [0x17] + [UInt8](repeating: 0xAA, count: 256)
            )
        }
    }

    @Test("Authorization token decoders reject truncated and trailing bytes")
    func rejectMalformedAuthorizationTokenBytes() {
        let validBytes = Self.rawAuthorizationTokenBytes()
        #expect(throws: OpalFusion.Mosaic.CanonicalCodingError.self) {
            _ = try Codec.decodeAuthorizationToken(from: Array(validBytes.dropLast()))
        }
        #expect(
            throws: OpalFusion.Mosaic.CanonicalCodingError.trailingBytes(1)
        ) {
            _ = try Codec.decodeAuthorizationToken(from: validBytes + [0x00])
        }
    }
}
