// OpalFusion+Host+EventObserver.swift

public extension OpalFusion.Host {
    protocol EventObserver: Sendable {
        func receive(
            _ event: OpalFusion.Host.Event,
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async
    }
}
