// OpalFusion+Execution+BCHTransaction.swift

import Foundation

package extension OpalFusion.Execution {
    struct BCHTransaction: Sendable, Equatable {
        package var version: Int32
        package var inputs: [OpalFusion.Execution.BCHTransaction.Input]
        package var outputs: [OpalFusion.Execution.BCHTransaction.Output]
        package var lockTime: UInt32

        package init(
            version: Int32,
            inputs: [OpalFusion.Execution.BCHTransaction.Input],
            outputs: [OpalFusion.Execution.BCHTransaction.Output],
            lockTime: UInt32
        ) {
            self.version = version
            self.inputs = inputs
            self.outputs = outputs
            self.lockTime = lockTime
        }










    }
}
