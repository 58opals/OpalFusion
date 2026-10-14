// OpalFusion+Execution+BCHTransaction+Input.swift

import Foundation

package extension OpalFusion.Execution.BCHTransaction {
    struct Input: Sendable, Equatable {
        package var previousTransactionHashLittleEndian: [UInt8]
        package var previousOutputIndex: UInt32
        package var unlockingScript: [UInt8]
        package var sequence: UInt32

        package init(
            previousTransactionHashLittleEndian: [UInt8],
            previousOutputIndex: UInt32,
            unlockingScript: [UInt8],
            sequence: UInt32
        ) {
            self.previousTransactionHashLittleEndian = previousTransactionHashLittleEndian
            self.previousOutputIndex = previousOutputIndex
            self.unlockingScript = unlockingScript
            self.sequence = sequence
        }
    }
}
