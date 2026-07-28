// OpalFusion+Execution+ProductionWorkflow.swift

import Foundation
import OpalCrypto
import OpalDiagnostics
extension OpalFusion.Execution {
    struct ProductionWorkflow: Sendable {
        let baseline: OpalFusion.Transport.BaselineConfiguration
        let pedersenSetup: OpalCrypto.Pedersen.Setup

        init(
            baseline: OpalFusion.Transport.BaselineConfiguration
        ) {
            self.baseline = baseline
            self.pedersenSetup = try! OpalCrypto.Pedersen.Setup()
        }































    }
}
