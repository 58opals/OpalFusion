// ClientErrorValidator.swift

import OpalFusion
import Testing

struct ClientErrorValidator {
    @Test("Client error exposes the documented additive cases")
    func validateClientErrorCases() {
        let errors: [OpalFusion.Client.Error] = [
            .invalidConfiguration,
            .transportUnavailable,
            .coordinatorRejected,
            .hostRejected,
            .protocolIncompatible,
            .blameRequired,
            .notImplemented
        ]

        #expect(errors.count == 7)
        #expect(Self.requireSendable(errors[0]) == .invalidConfiguration)
        #expect(errors[1] == .transportUnavailable)
        #expect(errors[2] == .coordinatorRejected)
        #expect(errors[3] == .hostRejected)
        #expect(errors[4] == .protocolIncompatible)
        #expect(errors[5] == .blameRequired)
        #expect(errors[6] == .notImplemented)
    }

    @Test("Client error keeps coordinator rejection distinct from host rejection and blame")
    func validateDistinctFailureCases() {
        #expect(OpalFusion.Client.Error.coordinatorRejected != .hostRejected)
        #expect(OpalFusion.Client.Error.protocolIncompatible != .blameRequired)
        #expect(OpalFusion.Client.Error.hostRejected != .blameRequired)
    }

    static func requireSendable<Value: Sendable>(_ value: Value) -> Value {
        value
    }
}
