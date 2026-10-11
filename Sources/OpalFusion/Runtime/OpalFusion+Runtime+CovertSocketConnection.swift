import Foundation
import Network

extension OpalFusion.Runtime {
    /// One framed exchange. After acknowledgement the socket is retained without
    /// scheduling more receives until the round owner cancels it.
    actor CovertSocketConnection {
        private let connection: NWConnection
        private let queue = DispatchQueue(label: "OpalFusion.Covert.Socket")
        private var readyContinuation: CheckedContinuation<Void, Error>?
        private var cancelled = false

        init(host: String, port: UInt16, parameters: NWParameters) {
            connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: parameters)
        }

        deinit { connection.cancel() }

        func exchange(_ frame: [UInt8], framing: OpalFusion.Transport.FrameConfiguration) async throws -> [UInt8] {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await start()
                try await send(frame)
                var decoder = OpalFusion.Wire.PrimaryFrameDecoder(configuration: framing)
                while true {
                    try Task.checkCancellation()
                    let bytes = try await receive()
                    if let payload = try decoder.append(bytes).first { return payload }
                }
            } onCancel: {
                Task { await self.cancel() }
            }
        }

        func cancel() {
            guard !cancelled else { return }
            cancelled = true
            readyContinuation?.resume(throwing: CancellationError())
            readyContinuation = nil
            connection.stateUpdateHandler = nil
            connection.cancel()
        }

        private func start() async throws {
            guard !cancelled else { throw CancellationError() }
            try await withCheckedThrowingContinuation { continuation in
                readyContinuation = continuation
                connection.stateUpdateHandler = { state in
                    Task { await self.stateChanged(state) }
                }
                connection.start(queue: queue)
            }
        }

        private func stateChanged(_ state: NWConnection.State) {
            switch state {
            case .ready:
                readyContinuation?.resume()
                readyContinuation = nil
                connection.stateUpdateHandler = nil
            case let .failed(error), let .waiting(error):
                readyContinuation?.resume(throwing: error)
                readyContinuation = nil
                cancel()
            case .cancelled:
                cancel()
            default: break
            }
        }

        private func send(_ bytes: [UInt8]) async throws {
            guard !cancelled else { throw CancellationError() }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: Data(bytes), completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                })
            }
        }

        private func receive() async throws -> [UInt8] {
            guard !cancelled else { throw CancellationError() }
            return try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let data, !data.isEmpty { continuation.resume(returning: Array(data)) }
                    else { continuation.resume(throwing: LiveTransportError.covertConnectionClosed) }
                }
            }
        }
    }
}
