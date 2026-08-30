// OpalFusion+MosaicPrivateAlphaRuntime+TorWebSocketConnectionAdapter.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    actor TorWebSocketConnectionAdapter:
        OpalFusion.Mosaic.TorWebSocketConnectioning
    {
        private let connection: any TorWebSocketConnection
        private let maximumPendingMessageCount: Int

        init(
            _ connection: any TorWebSocketConnection,
            maximumPendingMessageCount: Int
        ) throws {
            guard maximumPendingMessageCount > 0 else {
                throw Failure.invalidStateTransition
            }
            self.connection = connection
            self.maximumPendingMessageCount = maximumPendingMessageCount
        }

        func open(
            maximumIncomingMessageByteCount: Int
        ) async throws -> MessageStream {
            let source = try await connection.open(
                maximumIncomingMessageByteCount:
                    maximumIncomingMessageByteCount
            )
            let (stream, continuation) = MessageStream.makeStream(
                bufferingPolicy: .bufferingOldest(
                    maximumPendingMessageCount
                )
            )
            let connection = connection
            let task = Task {
                do {
                    for try await message in source {
                        let result: MessageStream.Continuation.YieldResult
                        switch message {
                        case let .text(bytes):
                            result = continuation.yield(.text(bytes))
                        case let .binary(bytes):
                            result = continuation.yield(.binary(bytes))
                        }
                        switch result {
                        case .enqueued:
                            break
                        case .dropped:
                            await connection.close()
                            continuation.finish(
                                throwing: Failure.invalidStateTransition
                            )
                            return
                        case .terminated:
                            return
                        @unknown default:
                            await connection.close()
                            continuation.finish(
                                throwing: Failure.invalidStateTransition
                            )
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await connection.close() }
            }
            return stream
        }

        func send(text: String) async throws {
            try await connection.send(text: text)
        }

        func close() async {
            await connection.close()
        }
    }
}
#endif
