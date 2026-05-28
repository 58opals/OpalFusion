// LiveRuntimeTestHarness.swift

import Foundation
import Darwin

enum LiveRuntimeTestHarness {
    static func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: duration)
                throw LiveRuntimeTestHarnessError.timedOut(
                    "Timed out after \(duration)"
                )
            }

            guard let result = try await group.next() else {
                throw LiveRuntimeTestHarnessError.missingTimeoutResult
            }
            group.cancelAll()
            return result
        }
    }

    static func reserveLoopbackPort() throws -> ReservedLoopbackPort {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw POSIXError(.EADDRNOTAVAIL)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(
                    socketDescriptor,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard bindResult == 0 else {
            _ = close(socketDescriptor)
            throw POSIXError(.EADDRNOTAVAIL)
        }

        var boundAddress = sockaddr_in()
        var boundAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(socketDescriptor, socketAddress, &boundAddressLength)
            }
        }
        guard nameResult == 0 else {
            _ = close(socketDescriptor)
            throw POSIXError(.EADDRNOTAVAIL)
        }

        return ReservedLoopbackPort(
            port: UInt16(bigEndian: boundAddress.sin_port),
            socketDescriptor: socketDescriptor
        )
    }
}
