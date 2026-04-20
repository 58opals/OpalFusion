// ReservedLoopbackPort.swift

import Darwin

final class ReservedLoopbackPort: @unchecked Sendable {
    let port: UInt16
    private var socketDescriptor: Int32?

    init(
        port: UInt16,
        socketDescriptor: Int32
    ) {
        self.port = port
        self.socketDescriptor = socketDescriptor
    }

    deinit {
        release()
    }

    func release() {
        guard let socketDescriptor else {
            return
        }

        _ = close(socketDescriptor)
        self.socketDescriptor = nil
    }
}
