// OpalFusion+Execution+ValidatedProof.swift

import Foundation
import OpalCrypto

extension OpalFusion.Execution {
    enum ValidatedProof: Sendable, Equatable {
        case input(OpalFusion.Commitment.InputComponent)
        case nonInput
    }
}
