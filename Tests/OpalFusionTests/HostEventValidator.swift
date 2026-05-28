// HostEventValidator.swift

import OpalFusion
import Testing

struct HostEventValidator {
    @Test("Event defaults kind to status and preserves payload")
    func validateDefaultEventKind() {
        let event = OpalFusion.Host.Event(
            phase: .connecting,
            summary: "Connecting to the coordinator"
        )

        #expect(event.kind == .status)
        #expect(event.phase == .connecting)
        #expect(event.summary == "Connecting to the coordinator")
        #expect(event.isTerminal == false)
    }

    @Test("Event kind exposes all documented cases")
    func validateEventKinds() throws {
        let kinds: [OpalFusion.Host.Event.Kind] = [
            .status,
            .warning,
            .failure,
            .completed
        ]

        #expect(kinds.count == 4)
        #expect(Self.requireSendable(try #require(kinds.first)) == .status)
        #expect(try #require(kinds.dropFirst().first) == .warning)
        #expect(try #require(kinds.dropFirst(2).first) == .failure)
        #expect(try #require(kinds.dropFirst(3).first) == .completed)
    }

    static func requireSendable<Value: Sendable>(_ value: Value) -> Value {
        value
    }
}
