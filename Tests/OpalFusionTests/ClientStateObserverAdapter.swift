// ClientStateObserverAdapter.swift

import OpalFusion

struct ClientStateObserverAdapter: OpalFusion.Client.StateObserver {
    func receive(_ snapshot: OpalFusion.Client.Session.Snapshot) async {}
}
