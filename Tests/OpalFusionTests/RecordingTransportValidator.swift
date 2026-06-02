// RecordingTransportValidator.swift

@testable import OpalFusion
import Testing

struct RecordingTransportValidator {
    @Test("Primary recorder preserves raw chunks while decoding messages")
    func validatePrimaryRawChunkRecording() async throws {
        let base = ScriptedPrimaryTransport()
        let recorder = RecordingPrimaryTransport(base: base)
        var inboundIterator = try await recorder.connect().makeAsyncIterator()
        let serverMessage = OpalFusion.ProtocolModel.ServerMessage.serverHello(
            PrimaryRuntimeTestFixtures.serverHello
        )
        let serverFrame = try Self.primaryFrame(for: serverMessage)
        let clientMessage = OpalFusion.ProtocolModel.ClientMessage.clientHello(
            PrimaryRuntimeTestFixtures.clientHello
        )
        let clientFrame = try Self.primaryFrame(for: clientMessage)

        await base.yieldInboundBytes(serverFrame)
        let receivedFrame = try #require(try await inboundIterator.next())
        try await recorder.write(clientFrame)

        #expect(receivedFrame == serverFrame)
        #expect(await recorder.recordedInboundPrimaryChunks == [serverFrame])
        #expect(await recorder.recordedOutboundPrimaryChunks == [clientFrame])
        #expect(await recorder.recordedServerMessages == [serverMessage])
        #expect(await recorder.recordedClientMessages == [clientMessage])
        #expect((await recorder.recordedInboundDecodeFailures).isEmpty)
        #expect((await recorder.recordedOutboundDecodeFailures).isEmpty)

        await recorder.close()
    }

    @Test("Covert recorder preserves raw payloads while decoding messages")
    func validateCovertRawPayloadRecording() async throws {
        let base = ScriptedCovertTransport()
        let recorder = RecordingCovertTransport(base: base)
        let response = OpalFusion.ProtocolModel.CovertResponse.acknowledgement(.init())
        let responsePayload = try OpalFusion.Wire.CovertMessageEncoder().encode(response)
        let message = OpalFusion.ProtocolModel.CovertMessage.ping(.init())
        let requestPayload = try OpalFusion.Wire.CovertMessageEncoder().encode(message)
        let request = OpalFusion.Runtime.CovertRequest(
            endpoint: PrimaryRuntimeTestFixtures.covertEndpointContext,
            payload: requestPayload,
            startedAt: .init(unixSeconds: 1),
            deadline: .init(unixSeconds: 2)
        )

        await base.enqueueResponse(responsePayload)
        let receivedResponsePayload = try await recorder.perform(request)

        #expect(receivedResponsePayload == responsePayload)
        #expect(await recorder.recordedRequestPayloads == [requestPayload])
        #expect(await recorder.recordedResponsePayloads == [responsePayload])
        #expect(await recorder.recordedRequestMessages == [message])
        #expect(await recorder.recordedResponses == [response])
        #expect((await recorder.recordedRequestDecodeFailures).isEmpty)
        #expect((await recorder.recordedResponseDecodeFailures).isEmpty)
    }

    private static func primaryFrame(
        for message: OpalFusion.ProtocolModel.ClientMessage
    ) throws -> [UInt8] {
        let payload = try OpalFusion.Wire.PrimaryMessageEncoder().encode(message)
        return try OpalFusion.Wire.PrimaryFrameEncoder(
            configuration: OpalFusion.Transport.BaselineConfiguration.electronCash443.framing
        ).encode(payload: payload)
    }

    private static func primaryFrame(
        for message: OpalFusion.ProtocolModel.ServerMessage
    ) throws -> [UInt8] {
        let payload = try OpalFusion.Wire.PrimaryMessageEncoder().encode(message)
        return try OpalFusion.Wire.PrimaryFrameEncoder(
            configuration: OpalFusion.Transport.BaselineConfiguration.electronCash443.framing
        ).encode(payload: payload)
    }
}
