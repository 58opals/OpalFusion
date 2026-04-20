// ReservedLoopbackPort.swift

import Darwin

actor ReservedLoopbackPort {
    private let portValue: UInt16
    private var socketDescriptor: Int32?

    init(
        port: UInt16,
        socketDescriptor: Int32
    ) {
        self.portValue = port
        self.socketDescriptor = socketDescriptor
    }

    deinit {
        if let socketDescriptor {
            _ = close(socketDescriptor)
        }
    }

    var port: UInt16 {
        portValue
    }

    func release() {
        guard let socketDescriptor else {
            return
        }

        _ = close(socketDescriptor)
        self.socketDescriptor = nil
    }
}
