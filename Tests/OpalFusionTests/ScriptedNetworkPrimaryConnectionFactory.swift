// ScriptedNetworkPrimaryConnectionFactory.swift

@testable import OpalFusion
import Network

struct ScriptedNetworkPrimaryConnectionFactory: Sendable {
    let connection: ScriptedNetworkPrimaryConnection

    init(
        startStates: [NWConnection.State],
        restartStates: [NWConnection.State] = []
    ) {
        self.connection = ScriptedNetworkPrimaryConnection(
            startStates: startStates,
            restartStates: restartStates
        )
    }

    func make(
        host _: String,
        port _: UInt16,
        parameters _: NWParameters
    ) -> any OpalFusion.Runtime.PrimaryConnectioning {
        connection
    }
}
