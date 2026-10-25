import Foundation
import Network

// Independent Electron Cash 4.4.3 connection.py framing. This peer deliberately
// uses neither the production frame codec nor an injected request executor.
actor CovertSocketTestServer {
    enum Reply: Sendable {
        case acknowledgement, silence, badMagic, oversized(Int), truncated
    }
    enum ProxyMode: Sendable { case disabled, accept, reject, stall, forward, rejectMethod, rejectAuthentication, truncatedReply }
    struct ProxyRequest: Sendable {
        let host: String
        let port: UInt16
        let username: String
        let password: String
    }
    let listener: NWListener
    let reply: Reply
    let proxyMode: ProxyMode
    let tunnelPort: UInt16?
    let proxyReply: [UInt8]?
    var tunnels: [NWConnection] = []
    private(set) var firstTunnelBytes: [UInt8] = []
    let queue = DispatchQueue(label: "OpalFusionTests.CovertSocket")
    var connections: [NWConnection] = []
    var startContinuation: CheckedContinuation<Void, Error>?
    private(set) var firstBytes: [UInt8] = []
    private(set) var payloads: [[UInt8]] = []
    private(set) var proxyRequests: [ProxyRequest] = []
    private(set) var closedConnectionCount = 0
    var connectionCount: Int { connections.count }
    var port: UInt16 { listener.port!.rawValue }

    init(listener: NWListener, reply: Reply, proxyMode: ProxyMode, tunnelPort: UInt16?, proxyReply: [UInt8]?) {
        self.listener = listener
        self.reply = reply
        self.proxyMode = proxyMode
        self.tunnelPort = tunnelPort
        self.proxyReply = proxyReply
    }

    static func start(
        reply: Reply = .acknowledgement,
        requiresTLS: Bool = false,
        proxyMode: ProxyMode = .disabled,
        tunnelPort: UInt16? = nil,
        proxyReply: [UInt8]? = nil
    ) async throws -> CovertSocketTestServer {
        let parameters = requiresTLS ? try await LoopbackPrimaryTLSTestFixture.makeListenerParameters() : NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let server = try CovertSocketTestServer(listener: NWListener(using: parameters), reply: reply, proxyMode: proxyMode, tunnelPort: tunnelPort, proxyReply: proxyReply)
        try await server.listen()
        return server
    }

    func listen() async throws {
        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            listener.stateUpdateHandler = { state in Task { await self.listenerChanged(state) } }
            listener.newConnectionHandler = { connection in Task { await self.accept(connection) } }
            listener.start(queue: queue)
        }
    }

    func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            startContinuation?.resume()
            startContinuation = nil
        case let .failed(error):
            startContinuation?.resume(throwing: error)
            startContinuation = nil
        default: break
        }
    }

    func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)
        Task {
            do {
                let requestedPort = try await negotiateProxy(connection)
                if proxyMode == .forward {
                    try await forwardTunnel(connection, requestedPort: requestedPort)
                    return
                }
                let header = try await read(12, from: connection)
                firstBytes = header
                guard Array(header.prefix(8)) == [0x76, 0x5b, 0xe8, 0xb4, 0xe4, 0x39, 0x6d, 0xcf] else {
                    throw LiveRuntimeTestHarnessError.inboundStreamClosed
                }
                let count = header.suffix(4).reduce(0) { ($0 << 8) | Int($1) }
                guard count <= 200 * 1024 else { throw LiveRuntimeTestHarnessError.inboundStreamClosed }
                payloads.append(try await read(count, from: connection))
                var frame: [UInt8] = [0x76, 0x5b, 0xe8, 0xb4, 0xe4, 0x39, 0x6d, 0xcf, 0, 0, 0, 2, 0x0a, 0]
                switch reply {
                case .acknowledgement:
                    for bytes in [Array(frame.prefix(3)), Array(frame[3..<13]), Array(frame.suffix(1))] {
                        try await send(bytes, to: connection)
                    }
                case .silence: break
                case .badMagic:
                    frame[0] = 0
                    try await send(frame, to: connection)
                case let .oversized(count):
                    let length = UInt32(count)
                    frame.replaceSubrange(8..<12, with: [UInt8(length >> 24), UInt8(truncatingIfNeeded: length >> 16), UInt8(truncatingIfNeeded: length >> 8), UInt8(truncatingIfNeeded: length)])
                    try await send(Array(frame.prefix(12)), to: connection)
                case .truncated:
                    try await send(Array(frame.prefix(13)), to: connection)
                    connection.cancel()
                }
                // A successful request must remain open until the owner resets.
                _ = try await read(1, from: connection)
            } catch { }
            closedConnectionCount += 1
            connection.cancel()
        }
    }

    private func negotiateProxy(_ connection: NWConnection) async throws -> UInt16? {
        guard proxyMode != .disabled else { return nil }
        let greeting = try await read(2, from: connection)
        guard greeting[0] == 5 else { throw LiveRuntimeTestHarnessError.inboundStreamClosed }
        let methods = try await read(Int(greeting[1]), from: connection)
        guard methods.contains(2) else { throw LiveRuntimeTestHarnessError.inboundStreamClosed }
        if proxyMode == .stall {
            _ = try await read(1, from: connection)
            throw LiveRuntimeTestHarnessError.inboundStreamClosed
        }
        if proxyMode == .rejectMethod {
            try await sendProxyReply([5, 0], to: connection)
            throw LiveRuntimeTestHarnessError.inboundStreamClosed
        }
        try await sendProxyReply([5, 2], to: connection)
        let authentication = try await read(2, from: connection)
        guard authentication[0] == 1 else { throw LiveRuntimeTestHarnessError.inboundStreamClosed }
        let username = try await read(Int(authentication[1]), from: connection)
        let passwordCount = try await read(1, from: connection)
        let password = try await read(Int(passwordCount[0]), from: connection)
        guard username == Array("<torS0X>0".utf8), !password.isEmpty else { throw LiveRuntimeTestHarnessError.inboundStreamClosed }
        if proxyMode == .rejectAuthentication {
            try await sendProxyReply([1, 1], to: connection)
            throw LiveRuntimeTestHarnessError.inboundStreamClosed
        }
        try await sendProxyReply([1, 0], to: connection)
        let request = try await read(4, from: connection)
        guard request[0...2] == [5, 1, 0] else { throw LiveRuntimeTestHarnessError.inboundStreamClosed }
        let host: String
        switch request[3] {
        case 3:
            let count = try await read(1, from: connection)
            host = String(decoding: try await read(Int(count[0]), from: connection), as: UTF8.self)
        case 1:
            host = try await read(4, from: connection).map(String.init).joined(separator: ".")
        case 4:
            let bytes = try await read(16, from: connection)
            host = IPv6Address(Data(bytes))!.debugDescription
        default: throw LiveRuntimeTestHarnessError.inboundStreamClosed
        }
        let port = try await read(2, from: connection)
        proxyRequests.append(.init(host: host, port: UInt16(port[0]) << 8 | UInt16(port[1]), username: String(decoding: username, as: UTF8.self), password: String(decoding: password, as: UTF8.self)))
        if proxyMode == .truncatedReply {
            try await sendProxyReply([5, 0, 0, 1, 127], to: connection)
            throw LiveRuntimeTestHarnessError.inboundStreamClosed
        }
        try await sendProxyReply(proxyReply ?? [5, proxyMode == .reject ? 5 : 0, 0, 1, 127, 0, 0, 1, 0, 0], to: connection)
        if proxyMode == .reject { throw LiveRuntimeTestHarnessError.inboundStreamClosed }
        return UInt16(port[0]) << 8 | UInt16(port[1])
    }

    private func sendProxyReply(_ bytes: [UInt8], to connection: NWConnection) async throws {
        for byte in bytes { try await send([byte], to: connection) }
    }

    private func forwardTunnel(_ connection: NWConnection, requestedPort: UInt16?) async throws {
        guard let tunnelPort = tunnelPort ?? requestedPort else { throw LiveRuntimeTestHarnessError.missingConnection }
        let upstream = NWConnection(host: "127.0.0.1", port: .init(rawValue: tunnelPort)!, using: .tcp)
        tunnels.append(upstream)
        upstream.start(queue: queue)
        firstTunnelBytes = try await read(5, from: connection)
        try await send(firstTunnelBytes, to: upstream)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.pipe(connection, to: upstream) }
            group.addTask { try await self.pipe(upstream, to: connection) }
            defer {
                upstream.cancel()
                connection.cancel()
                group.cancelAll()
            }
            _ = try await group.next()
        }
    }

    private func pipe(_ source: NWConnection, to destination: NWConnection) async throws {
        while true {
            let bytes: [UInt8] = try await withCheckedThrowingContinuation { continuation in
                source.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let data, !data.isEmpty { continuation.resume(returning: Array(data)) }
                    else { continuation.resume(throwing: LiveRuntimeTestHarnessError.inboundStreamClosed) }
                }
            }
            try await send(bytes, to: destination)
        }
    }

    func waitFor(payloadCount: Int? = nil, connectionCount: Int? = nil, closedCount: Int? = nil) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while payloadCount.map({ payloads.count < $0 }) == true || connectionCount.map({ connections.count < $0 }) == true || closedCount.map({ closedConnectionCount < $0 }) == true {
            guard ContinuousClock.now < deadline else { throw LiveRuntimeTestHarnessError.timedOut("Covert peer observation") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func read(_ count: Int, from connection: NWConnection) async throws -> [UInt8] {
        if count == 0 { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, data.count == count { continuation.resume(returning: Array(data)) }
                else { continuation.resume(throwing: LiveRuntimeTestHarnessError.inboundStreamClosed) }
            }
        }
    }

    func send(_ bytes: [UInt8], to connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    func stop() {
        for connection in tunnels { connection.cancel() }
        for connection in connections { connection.cancel() }
        listener.cancel()
    }
}
