// OpalFusion+Mosaic+TorWebSocketConnectioning.swift

import Foundation

extension OpalFusion.Mosaic {
    enum TorWebSocketMessage: Sendable, Equatable {
        /// Bounded UTF-8 bytes from a WebSocket text message.
        case text(Data)
        case binary(Data)
    }

    /// An injected WebSocket that is already constrained to a Tor-only route.
    ///
    /// This capability has no direct-network case and no production default implementation. Its
    /// implementation must enforce `maximumIncomingMessageByteCount` before materializing or
    /// delivering a WebSocket message, and `close()` must terminate pending `open` and `send`
    /// operations.
    protocol TorWebSocketConnectioning: Actor {
        typealias MessageStream = AsyncThrowingStream<TorWebSocketMessage, Swift.Error>

        func open(
            maximumIncomingMessageByteCount: Int
        ) async throws -> MessageStream
        func send(text: String) async throws
        func close() async
    }
}
