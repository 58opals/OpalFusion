// OpalFusion+Execution+BCHTransaction+Output.swift

import Foundation

package extension OpalFusion.Execution.BCHTransaction {
    struct Output: Sendable, Equatable {
        package var amountSatoshis: UInt64
        package var lockingScript: [UInt8]

        package init(amountSatoshis: UInt64, lockingScript: [UInt8]) {
            self.amountSatoshis = amountSatoshis
            self.lockingScript = lockingScript
        }
    }
}
