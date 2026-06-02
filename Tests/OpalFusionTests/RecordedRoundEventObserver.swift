// RecordedRoundEventObserver.swift

@testable import OpalFusion
import Foundation

actor RecordedRoundEventObserver: OpalFusion.Host.EventObserver {
    private var events: [RecordedRoundEvent] = []
    private var timedEvents: [TimedRecordedRoundEvent] = []

    func receive(
        _ event: OpalFusion.Host.Event,
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async {
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

    var recordedSnapshots: [RecordedRoundEvent] {
        events
    }

    var timedSnapshots: [TimedRecordedRoundEvent] {
        timedEvents
    }
}
