// ClientErrorValidator.swift

import OpalFusion
import Testing

struct ClientErrorValidator {
    @Test("Client error exposes the documented additive cases")
    func validateClientErrorCases() throws {
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
        #expect(Self.requireSendable(try #require(errors.first)) == .invalidConfiguration)
        #expect(try #require(errors.dropFirst().first) == .transportUnavailable)
        #expect(try #require(errors.dropFirst(2).first) == .coordinatorRejected)
        #expect(try #require(errors.dropFirst(3).first) == .hostRejected)
        #expect(try #require(errors.dropFirst(4).first) == .protocolIncompatible)
        #expect(try #require(errors.dropFirst(5).first) == .blameRequired)
        #expect(try #require(errors.dropFirst(6).first) == .notImplemented)
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
