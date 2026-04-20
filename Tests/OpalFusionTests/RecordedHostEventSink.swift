// RecordedHostEventSink.swift

@testable import OpalFusion
import Foundation

actor RecordedHostEventSink {
    private var events: [RecordedHostEvent] = []
    private var timedEvents: [TimedRecordedHostEvent] = []

    func record(
        roundIdentifier: OpalFusion.Round.Identifier?,
        event: OpalFusion.Host.Event
    ) {
        timedEvents.append(
            .init(
                roundIdentifier: roundIdentifier,
                event: event,
                recordedAt: Date()
            )
        )
        events.append(
            .init(
                roundIdentifier: roundIdentifier,
                event: event
            )
        )
    }

    func snapshot() -> [RecordedHostEvent] {
        events
    }

    func timedSnapshot() -> [TimedRecordedHostEvent] {
        timedEvents
    }
}
