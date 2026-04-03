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
    func validateEventKinds() {
        let kinds: [OpalFusion.Host.Event.Kind] = [
            .status,
            .warning,
            .failure,
            .completed
        ]

        #expect(kinds.count == 4)
        #expect(Self.requireSendable(kinds[0]) == .status)
        #expect(kinds[1] == .warning)
        #expect(kinds[2] == .failure)
        #expect(kinds[3] == .completed)
    }

    static func requireSendable<Value: Sendable>(_ value: Value) -> Value {
        value
    }
}
