// OpalFusion+Execution+BCHTransaction.swift

import Foundation

extension OpalFusion.Execution {
    struct BCHTransaction: Sendable, Equatable {
        var version: Int32
        var inputs: [OpalFusion.Execution.BCHTransaction.Input]
        var outputs: [OpalFusion.Execution.BCHTransaction.Output]
        var lockTime: UInt32










    }
}
