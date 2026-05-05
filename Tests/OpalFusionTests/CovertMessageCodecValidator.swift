// CovertMessageCodecValidator.swift

@testable import OpalFusion
import Testing

struct CovertMessageCodecValidator {
    @Test("Covert protobuf bridge round-trips all modeled covert client messages")
    func validateCovertMessageRoundTrips() throws {
        let encoder = OpalFusion.Wire.CovertMessageEncoder()
        let decoder = OpalFusion.Wire.CovertMessageDecoder()

        for message in PrimaryRuntimeTestFixtures.covertMessages {
            let payload = try encoder.encode(message)
            let decoded = try decoder.decodeMessage(payload)
            #expect(decoded == message)
        }
    }

    @Test("Covert protobuf bridge round-trips acknowledgement and server failure responses")
    func validateCovertResponseRoundTrips() throws {
        let encoder = OpalFusion.Wire.CovertMessageEncoder()
        let decoder = OpalFusion.Wire.CovertMessageDecoder()

        for response in PrimaryRuntimeTestFixtures.covertResponses {
            let payload = try encoder.encode(response)
            let decoded = try decoder.decodeResponse(payload)
            #expect(decoded == response)
        }
    }

    @Test("Covert protobuf bridge preserves optional round public keys")
    func validateOptionalRoundPublicKeyPreservation() throws {
        let componentPayload = try OpalFusion.Wire.CovertMessageEncoder()
            .encode(PrimaryRuntimeTestFixtures.covertComponentMessage)
        let signaturePayload = try OpalFusion.Wire.CovertMessageEncoder()
            .encode(PrimaryRuntimeTestFixtures.signatureMessage)

        let componentEnvelope = try FusionCovertMessage(serializedBytes: componentPayload)
        let signatureEnvelope = try FusionCovertMessage(serializedBytes: signaturePayload)

        guard case let .component(component)? = componentEnvelope.msg else {
            Issue.record("Expected covert component envelope")
            return
        }
        guard case let .signature(signature)? = signatureEnvelope.msg else {
            Issue.record("Expected covert signature envelope")
            return
        }

        #expect(component.hasRoundPubkey)
        #expect(signature.hasRoundPubkey)
        #expect([UInt8](component.roundPubkey) == [0xAA, 0xBB])
        #expect([UInt8](signature.roundPubkey) == [0xAA, 0xBB])
    }

    @Test("Covert protobuf bridge rejects malformed covert response payloads")
    func validateMalformedCovertResponsePayload() {
        do {
            _ = try OpalFusion.Wire.CovertMessageDecoder().decodeResponse([0x08])
            Issue.record("Expected covert response decode failure")
        } catch let error as OpalFusion.Wire.CovertMessageCodecError {
            switch error {
            case let .protobufCodingFailed(summary):
                #expect(summary.isEmpty == false)
            default:
                Issue.record("Unexpected codec error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
