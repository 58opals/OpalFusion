// OpalFusion+Runtime+CovertTransporting.swift

import CFNetwork
import Foundation
import Network
import OSLog
import Security

extension OpalFusion.Runtime {
    protocol CovertTransporting: Sendable {
        func prepare(_ plan: OpalFusion.Runtime.CovertPreparationPlan) async throws
        func perform(_ request: OpalFusion.Runtime.CovertRequest) async throws -> [UInt8]
        func reset() async
    }
}
