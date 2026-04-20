// HostEventObserverAdapter.swift

import OpalFusion

struct HostEventObserverAdapter: OpalFusion.Host.EventObserver {
    func receive(
        _ event: OpalFusion.Host.Event,
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async {}
}
