// OpalFusion+Execution+BCHTransactionError.swift

import Foundation

extension OpalFusion.Execution {
    enum BCHTransactionError: Swift.Error, Sendable, Equatable {
        case malformed(String)
        case templateMismatch(String)
        case unsupportedInput(String)
    }
}
