import OpalFusionCore

import Foundation
import Network

extension OpalFusion.Runtime {
    /// Negotiates SOCKS on a TCP connection whose only destination is the proxy.
    /// Network.framework serializes this instance's protocol callbacks.
    final class SOCKS5Framer: NWProtocolFramerImplementation {
        static let label = "OpalFusion SOCKS5"
        static let definition = NWProtocolFramer.Definition(implementation: SOCKS5Framer.self)

        private enum Phase {
            case method, authentication, replyHeader, domainLength, address(Int), ready, failed
        }
        private var phase = Phase.method
        private let authentication: Data
        private let connectCommand: Data
        private let tlsOptions: NWProtocolTLS.Options?

        required init(framer: NWProtocolFramer.Instance) {
            authentication = framer.options["authentication"] as? Data ?? Data()
            connectCommand = framer.options["connect"] as? Data ?? Data()
            tlsOptions = framer.options["tls"] as? NWProtocolTLS.Options
        }

        static func options(host: String, port: UInt16, isolationID: UUID, tls: NWProtocolTLS.Options?) -> NWProtocolFramer.Options {
            let options = NWProtocolFramer.Options(definition: definition)
            // Tor SOCKS format 0; distinct passwords retain per-socket isolation.
            let username = Array("<torS0X>0".utf8)
            let isolation = Array(isolationID.uuidString.utf8)
            options["authentication"] = Data([1, UInt8(username.count)] + username + [UInt8(isolation.count)] + isolation)
            var command: [UInt8] = [5, 1, 0]
            switch NWEndpoint.Host(host) {
            case let .ipv4(address): command += [1] + Array(address.rawValue)
            case let .ipv6(address): command += [4] + Array(address.rawValue)
            case .name:
                let name = Array(host.utf8)
                // Host validation limits a DNS name to 253 bytes plus a final dot.
                command += [3, UInt8(name.count)] + name
            @unknown default: break
            }
            command += [UInt8(port >> 8), UInt8(truncatingIfNeeded: port)]
            options["connect"] = Data(command)
            options["tls"] = tls
            return options
        }

        func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult {
            guard !authentication.isEmpty, !connectCommand.isEmpty else {
                fail(framer)
                return .willMarkReady
            }
            // Require username/password so Tor can isolate each connection.
            framer.writeOutput(data: Data([5, 1, 2]))
            return .willMarkReady
        }

        func handleInput(framer: NWProtocolFramer.Instance) -> Int {
            while true {
                switch phase {
                case .method:
                    guard let bytes = read(2, from: framer) else { return 2 }
                    guard bytes == [5, 2] else { fail(framer); return 0 }
                    phase = .authentication
                    framer.writeOutput(data: authentication)
                case .authentication:
                    guard let bytes = read(2, from: framer) else { return 2 }
                    guard bytes == [1, 0] else { fail(framer); return 0 }
                    phase = .replyHeader
                    framer.writeOutput(data: connectCommand)
                case .replyHeader:
                    guard let bytes = read(4, from: framer) else { return 4 }
                    guard bytes[0] == 5, bytes[1] == 0, bytes[2] == 0 else { fail(framer); return 0 }
                    switch bytes[3] {
                    case 1: phase = .address(4 + 2)
                    case 4: phase = .address(16 + 2)
                    case 3: phase = .domainLength
                    default: fail(framer); return 0
                    }
                case .domainLength:
                    guard let bytes = read(1, from: framer) else { return 1 }
                    guard bytes[0] > 0 else { fail(framer); return 0 }
                    phase = .address(Int(bytes[0]) + 2)
                case let .address(count):
                    guard read(count, from: framer) != nil else { return count }
                    do {
                        // Apple supports inserting TLS above a handshaking framer
                        // before markReady; TLS then authenticates the target host.
                        if let tlsOptions { try framer.prependApplicationProtocol(options: tlsOptions) }
                        phase = .ready
                        framer.passThroughInput()
                        framer.passThroughOutput()
                        framer.markReady()
                    } catch { fail(framer) }
                    return 0
                case .ready, .failed: return 0
                }
            }
        }

        private func read(_ count: Int, from framer: NWProtocolFramer.Instance) -> [UInt8]? {
            var result: [UInt8]?
            _ = framer.parseInput(minimumIncompleteLength: count, maximumLength: count) { buffer, isComplete in
                guard let buffer, buffer.count >= count else {
                    if isComplete { fail(framer) }
                    return 0
                }
                result = Array(buffer.prefix(count))
                return count
            }
            return result
        }

        private func fail(_ framer: NWProtocolFramer.Instance) {
            phase = .failed
            framer.markFailed(error: .posix(.EPROTO))
        }

        func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message, messageLength: Int, isComplete: Bool) {
            // Application/TLS output must remain blocked until SOCKS succeeds;
            // after success passThroughOutput bypasses this callback entirely.
            fail(framer)
        }
        func wakeup(framer: NWProtocolFramer.Instance) { }
        func stop(framer: NWProtocolFramer.Instance) -> Bool { true }
        func cleanup(framer: NWProtocolFramer.Instance) { }
    }
}
