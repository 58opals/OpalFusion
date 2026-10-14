// ClientStateObserverAdapter.swift

import CashFusionEngine
import OpalFusionCore
struct ClientStateObserverAdapter: OpalFusion.Client.StateObserver {
    func receive(_ snapshot: OpalFusion.Client.Session.Snapshot) async {}
}
