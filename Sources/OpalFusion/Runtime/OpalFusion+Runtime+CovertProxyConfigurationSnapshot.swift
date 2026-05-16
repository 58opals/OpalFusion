// OpalFusion+Runtime+CovertProxyConfigurationSnapshot.swift

import CFNetwork
import Foundation
import Network
import Security

extension OpalFusion.Runtime {
    struct CovertProxyConfigurationSnapshot: Sendable, Equatable {
        let socksEnabled: Bool
        let proxyHost: String?
        let proxyPort: Int?
    }
}
