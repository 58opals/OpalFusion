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
}
