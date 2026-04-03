// HostEventObserverAdapter.swift

import OpalFusion

final class HostEventObserverAdapter: Sendable, OpalFusion.Host.EventObserver {
    func receive(
        _ event: OpalFusion.Host.Event,
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async {}
}
