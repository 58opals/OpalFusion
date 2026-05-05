// OpalFusion+Execution+RelayedProofValidationFailure.swift

import Foundation
import OpalCrypto
import SwiftProtobuf

extension OpalFusion.Execution {
    struct RelayedProofValidationFailure: Swift.Error, Sendable, Equatable {
        let reason: String
    }
}
