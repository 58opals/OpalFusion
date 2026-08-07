// MosaicRelayPublicationTrackerValidator.swift

import Testing
@testable import OpalFusion

@Suite("Mosaic relay publication quorum validation")
struct MosaicRelayPublicationTrackerValidator {
    typealias Tracker = OpalFusion.Mosaic.RelayPublicationTracker

    @Test("Require at least three distinct validated relay endpoints")
    func requireThreeDistinctRelays() {
        let first = endpoint(1)
        #expect(
            throws: Tracker.ValidationError.fewerThanThreeRelays(actual: 2)
        ) {
            _ = try Tracker(endpoints: [first, endpoint(2)])
        }
        #expect(throws: Tracker.ValidationError.duplicateRelay(first)) {
            _ = try Tracker(endpoints: [first, endpoint(2), first])
        }
    }

    @Test("Succeed after every relay was attempted and any two accepted")
    func succeedAfterAllAttemptsAndTwoAcceptances() throws {
        let endpoints = [endpoint(1), endpoint(2), endpoint(3)]
        var tracker = try Tracker(endpoints: endpoints)

        try tracker.markAttempted(endpoints[0])
        try tracker.markAttempted(endpoints[1])
        try tracker.record(.accepted, from: endpoints[0])
        try tracker.record(.accepted, from: endpoints[1])
        #expect(tracker.status == .awaitingResponses)
        try tracker.markAttempted(endpoints[2])
        #expect(tracker.status == .accepted)

        try tracker.markAttempted(endpoints[2])
        #expect(tracker.status == .accepted)
    }

    @Test("Do not let silent extra relays block a two-acceptance quorum")
    func tolerateSilentExtraRelays() throws {
        let endpoints = (1 ... 4).map(endpoint)
        var tracker = try Tracker(endpoints: endpoints)
        for endpoint in endpoints {
            try tracker.markAttempted(endpoint)
        }
        try tracker.record(.accepted, from: endpoints[0])
        try tracker.record(.accepted, from: endpoints[1])

        #expect(tracker.status == .accepted)
    }

    @Test("Fail one-acceptance publication and reject bad responses")
    func failOneAcceptanceAndRejectBadResponses() throws {
        let endpoints = [endpoint(1), endpoint(2), endpoint(3)]
        var tracker = try Tracker(endpoints: endpoints)
        for endpoint in endpoints {
            try tracker.markAttempted(endpoint)
        }
        try tracker.record(.accepted, from: endpoints[0])
        try tracker.record(.rejected, from: endpoints[1])
        try tracker.record(.rejected, from: endpoints[2])
        #expect(tracker.status == .failed)

        #expect(
            throws: Tracker.RecordError.conflictingResponse(endpoints[0])
        ) {
            try tracker.record(.rejected, from: endpoints[0])
        }
        let outsider = endpoint(4)
        #expect(throws: Tracker.RecordError.unknownRelay(outsider)) {
            try tracker.record(.accepted, from: outsider)
        }

        var unattempted = try Tracker(endpoints: endpoints)
        #expect(throws: Tracker.RecordError.relayNotAttempted(endpoints[0])) {
            try unattempted.record(.accepted, from: endpoints[0])
        }
    }

    private func endpoint(_ value: Int) -> Tracker.Endpoint {
        .init(validatedIdentifier: "relay-\(value)")
    }
}
