// KeepaliveProtocolValidator.swift

import OpalFusion
import Testing

struct KeepaliveProtocolValidator {
    @Test("Keepalive protocol models remain sendable and equatable")
    func validateKeepaliveProtocolModels() {
        let ping = OpalFusion.ProtocolModel.Ping()
        let acknowledgement = OpalFusion.ProtocolModel.Acknowledgement()

        #expect(Self.requireSendable(ping) == ping)
        #expect(Self.requireSendable(acknowledgement) == acknowledgement)
        #expect(ping == .init())
        #expect(acknowledgement == .init())
    }

    static func requireSendable<Value: Sendable>(_ value: Value) -> Value {
        value
    }
}
