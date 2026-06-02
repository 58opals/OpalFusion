// OpalFusion+Runtime+NetworkPrimaryConnection+ImplementationGroup3.swift

import CFNetwork
import Foundation
import Network
import OpalDiagnostics
import Security

extension OpalFusion.Runtime.NetworkPrimaryConnection {
    func finishEventStream() {
        guard let eventContinuation else {
            return
        }

        self.eventContinuation = nil
        eventContinuation.finish()
    }

    func resetState(
        cancelUnderlying: Bool
    ) {
        waitingRestartTask?.cancel()
        waitingRestartTask = nil
        connection.stateUpdateHandler = nil
        if cancelUnderlying {
            connection.cancel()
        }
        readyContinuation = nil
        lastNonCancellationTransportError = nil
        isReady = false
        isReceivePending = false
        isExplicitlyClosing = false
        didObservePeerEOF = false
    }
}
