// OpalFusion+Runtime+CovertEndpointContext.swift

extension OpalFusion.Runtime {
    struct CovertEndpointContext: Sendable, Equatable {
        let roundIdentifier: OpalFusion.Round.Identifier?
        let host: String
        let port: UInt32
        let requiresTLS: Bool?
        let entryPath: String
        let maxPayloadBytes: Int
        let requestTimeoutMilliseconds: UInt64
        let connectTimeout: Duration
        let connectWindow: Duration
        let submitTimeout: Duration
        let submitWindow: Duration
        let spareConnectionCount: Int
    }
}
