// OpalFusion+Execution+BCHTransaction+Input.swift

import Foundation

extension OpalFusion.Execution.BCHTransaction {
    struct Input: Sendable, Equatable {
        var previousTransactionHashLittleEndian: [UInt8]
        var previousOutputIndex: UInt32
        var unlockingScript: [UInt8]
        var sequence: UInt32
    }
}
