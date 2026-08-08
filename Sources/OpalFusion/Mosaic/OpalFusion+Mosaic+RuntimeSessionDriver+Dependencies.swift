// OpalFusion+Mosaic+RuntimeSessionDriver+Dependencies.swift

extension OpalFusion.Mosaic.RuntimeSessionDriver {
    /// Input and ordered-output seams for one post-admission runtime.
    ///
    /// Each input must have passed the validation owned by its transport, local-operation, or
    /// wallet-host boundary. The output sink must synchronously accept every output in order. It
    /// must not perform asynchronous wallet work or call back into the driver; a later executor
    /// owns those operations and their explicit success or failure inputs.
    struct Dependencies: Sendable {
        typealias InputStream = AsyncThrowingStream<
            OpalFusion.Mosaic.RuntimeSession.Input,
            Error
        >
        typealias OpenInputStream = @Sendable () async throws -> InputStream
        typealias CloseInputSource = @Sendable () async -> Void
        typealias OutputSink = @Sendable (Output) -> Void

        let openInputStream: OpenInputStream
        let closeInputSource: CloseInputSource
        let outputSink: OutputSink

        init(
            openInputStream: @escaping OpenInputStream,
            closeInputSource: @escaping CloseInputSource,
            outputSink: @escaping OutputSink
        ) {
            self.openInputStream = openInputStream
            self.closeInputSource = closeInputSource
            self.outputSink = outputSink
        }
    }
}
