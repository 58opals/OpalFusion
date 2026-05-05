// OpalFusion+Execution+SessionContext.swift

import OpalCrypto

extension OpalFusion.Execution {
    struct SessionContext: Sendable, Equatable {
        let configuration: OpalFusion.Client.Configuration
        let baseline: OpalFusion.Transport.BaselineConfiguration
        let genesisHash: [UInt8]?
        let joinPools: OpalFusion.ProtocolModel.JoinPools
        var latestServerHello: OpalFusion.ProtocolModel.ServerHello?
        var latestTierStatus: OpalFusion.ProtocolModel.TierStatusUpdate?
        var isConnected: Bool
        var restartCount: Int
        var connectionSubstate: OpalFusion.Execution.ConnectionSubstate
        var lastError: OpalFusion.Client.Error?
        var lastErrorSummary: String?

        init(
            configuration: OpalFusion.Client.Configuration,
            baseline: OpalFusion.Transport.BaselineConfiguration,
            genesisHash: [UInt8]?,
            joinPools: OpalFusion.ProtocolModel.JoinPools
        ) {
            self.configuration = configuration
            self.baseline = baseline
            self.genesisHash = genesisHash
            self.joinPools = joinPools
            self.latestServerHello = nil
            self.latestTierStatus = nil
            self.isConnected = false
            self.restartCount = 0
            self.connectionSubstate = .disconnected
            self.lastError = nil
            self.lastErrorSummary = nil
        }
    }
}
