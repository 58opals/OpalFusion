// OpalFusion+Execution+RelayedProofValidationFailure.swift

import Foundation
import OpalCrypto

extension OpalFusion.Execution {
    struct RelayedProofValidationFailure: Swift.Error, Sendable, Equatable {
        let reason: String
    }
}
