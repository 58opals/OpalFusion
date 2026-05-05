// OpalFusion+Execution+BCHTransaction+Output.swift

import Foundation

extension OpalFusion.Execution.BCHTransaction {
    struct Output: Sendable, Equatable {
        var amountSatoshis: UInt64
        var lockingScript: [UInt8]
    }
}
