// RecordingPrimaryTransport.swift

@testable import OpalFusion

actor RecordingPrimaryTransport: OpalFusion.Runtime.PrimaryTransporting {
    private let base: any OpalFusion.Runtime.PrimaryTransporting
    private var outboundFrameDecoder: OpalFusion.Wire.PrimaryFrameDecoder
    private var inboundFrameDecoder: OpalFusion.Wire.PrimaryFrameDecoder
    private let messageDecoder: OpalFusion.Wire.PrimaryMessageDecoder
    private(set) var clientMessages: [OpalFusion.ProtocolModel.ClientMessage]
    private(set) var serverMessages: [OpalFusion.ProtocolModel.ServerMessage]
    private(set) var outboundDecodeFailures: [String]
    private(set) var inboundDecodeFailures: [String]

    init(
        base: any OpalFusion.Runtime.PrimaryTransporting,
        baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443
    ) {
        self.base = base
        self.outboundFrameDecoder = .init(configuration: baseline.framing)
        self.inboundFrameDecoder = .init(configuration: baseline.framing)
        self.messageDecoder = .init()
        self.clientMessages = []
        self.serverMessages = []
        self.outboundDecodeFailures = []
        self.inboundDecodeFailures = []
    }

    func connect() async throws -> AsyncThrowingStream<[UInt8], Error> {
        let inboundStream = try await base.connect()
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: [UInt8].self,
            throwing: Error.self
        )

        Task {
            do {
                for try await bytes in inboundStream {
                    self.recordInbound(bytes)
                    continuation.yield(bytes)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        return stream
    }

    func write(_ bytes: [UInt8]) async throws {
        try await base.write(bytes)
        recordOutbound(bytes)
    }

    func close() async {
        await base.close()
    }

    private func recordOutbound(_ bytes: [UInt8]) {
        do {
            let payloads = try outboundFrameDecoder.append(bytes)
            for payload in payloads {
                clientMessages.append(try messageDecoder.decodeClient(payload))
            }
        } catch {
            outboundDecodeFailures.append(String(describing: error))
        }
    }

    private func recordInbound(_ bytes: [UInt8]) {
        do {
            let payloads = try inboundFrameDecoder.append(bytes)
            for payload in payloads {
                serverMessages.append(try messageDecoder.decodeServer(payload))
            }
        } catch {
            inboundDecodeFailures.append(String(describing: error))
        }
    }

    func recordedClientMessages() -> [OpalFusion.ProtocolModel.ClientMessage] {
        clientMessages
    }

    func recordedServerMessages() -> [OpalFusion.ProtocolModel.ServerMessage] {
        serverMessages
    }

    func recordedOutboundDecodeFailures() -> [String] {
        outboundDecodeFailures
    }

    func recordedInboundDecodeFailures() -> [String] {
        inboundDecodeFailures
    }
}
