// HostEventObserverAdapter.swift

import CashFusionEngine
import OpalFusionCore
struct HostEventObserverAdapter: OpalFusion.Host.EventObserver {
    func receive(
        _ event: OpalFusion.Host.Event,
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async {}
}
