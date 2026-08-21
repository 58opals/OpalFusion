// OpalFusion+MosaicPrivateAlphaRuntime+TorWebSocketConnection.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// App-owned WebSocket capability already constrained to one Tor-only route.
    ///
    /// `close()` must be idempotent, finish the message stream, unblock pending
    /// `open` and `send` work, and return only after that connection is closed.
    @_spi(MosaicPrivateAlpha)
    public protocol TorWebSocketConnection: Actor {
        typealias MessageStream = AsyncThrowingStream<
            TorWebSocketMessage,
            Swift.Error
        >

        func open(
            maximumIncomingMessageByteCount: Int
        ) async throws -> MessageStream
        func send(text: String) async throws
        func close() async
    }
}
#endif
