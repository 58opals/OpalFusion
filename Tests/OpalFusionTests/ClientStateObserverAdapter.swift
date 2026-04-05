// ClientStateObserverAdapter.swift

import OpalFusion

final class ClientStateObserverAdapter: Sendable, OpalFusion.Client.StateObserver {
    func receive(_ snapshot: OpalFusion.Client.Session.Snapshot) async {}
}
