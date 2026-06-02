// ElectronCashTranscriptCaptureLiteralEmitterValidator.swift

import Testing

struct ElectronCashTranscriptCaptureLiteralEmitterValidator {
    @Test("Electron Cash transcript capture formatter emits deterministic Swift literals")
    func validateSwiftFixtureCandidateFormatting() {
        let capture = ElectronCashTranscriptCapture(
            primaryInboundChunks: [[0x00, 0x0F, 0x10, 0xFF]],
            primaryOutboundChunks: [[]],
            covertRequestPayloads: [[0x0A, 0x01, 0xAA]],
            covertResponsePayloads: [[0x0A, 0x00]],
            clientMessageKinds: ["clientHello", "joinPools"],
            serverMessageKinds: ["serverHello"],
            covertMessageKinds: ["component"],
            covertResponseKinds: ["acknowledgement"],
            roundOutcomes: ["success"],
            eventSummaries: ["event \"quoted\" \\ path\nnext"]
        )

        let output = ElectronCashTranscriptCaptureLiteralEmitter.makeSwiftFixtureCandidate(
            for: capture
        )

        #expect(
            output == ElectronCashTranscriptCaptureLiteralEmitter.makeSwiftFixtureCandidate(
                for: capture
            )
        )
        #expect(output.contains("static let primaryInboundChunks: [[UInt8]] = ["))
        #expect(output.contains("        [0x00, 0x0F, 0x10, 0xFF],"))
        #expect(output.contains("        [],"))
        #expect(output.contains("        \"event \\\"quoted\\\" \\\\ path\\nnext\","))
        #expect(output.contains("Captured from the env-gated Electron Cash interop smoke."))
    }

    @Test("Electron Cash transcript capture formatter omits sensitive labels")
    func validateSensitiveLabelsAreOmitted() {
        let output = ElectronCashTranscriptCaptureLiteralEmitter.makeSwiftFixtureCandidate(
            for: .init(
                primaryInboundChunks: [],
                primaryOutboundChunks: [],
                covertRequestPayloads: [],
                covertResponsePayloads: [],
                clientMessageKinds: [],
                serverMessageKinds: [],
                covertMessageKinds: [],
                covertResponseKinds: [],
                roundOutcomes: [],
                eventSummaries: []
            )
        )

        #expect(output.contains("static let primaryInboundChunks: [[UInt8]] = ["))
        #expect(output.contains("static let eventSummaries: [String] = ["))
        for sensitiveLabel in [
            "OPALFUSION_EC_INPUT_PRIVATE_KEY_HEX",
            "OPALFUSION_EC_COORDINATOR_HOST",
            "OPALFUSION_EC_TOR_SOCKS5_HOST",
            "coordinatorHost",
            "torSocks5",
            "environment =",
            "127.0.0.1",
        ] {
            #expect(output.contains(sensitiveLabel) == false)
        }
    }

    @Test("Electron Cash transcript capture formatter marks and extracts candidates")
    func validateMarkedFixtureCandidateExtraction() {
        let capture = ElectronCashTranscriptCapture(
            primaryInboundChunks: [[0x01]],
            primaryOutboundChunks: [[0x02]],
            covertRequestPayloads: [],
            covertResponsePayloads: [],
            clientMessageKinds: ["clientHello"],
            serverMessageKinds: ["serverHello"],
            covertMessageKinds: [],
            covertResponseKinds: [],
            roundOutcomes: ["success"],
            eventSummaries: []
        )
        let candidate = ElectronCashTranscriptCaptureLiteralEmitter.makeSwiftFixtureCandidate(
            for: capture
        )
        let markedCandidate = ElectronCashTranscriptCaptureLiteralEmitter.makeMarkedSwiftFixtureCandidate(
            for: capture
        )

        #expect(markedCandidate.contains(ElectronCashTranscriptCaptureLiteralEmitter.beginMarker))
        #expect(markedCandidate.contains(ElectronCashTranscriptCaptureLiteralEmitter.endMarker))
        #expect(
            ElectronCashTranscriptCaptureLiteralEmitter.extractSwiftFixtureCandidate(
                from: markedCandidate
            ) == candidate
        )
        #expect(
            ElectronCashTranscriptCaptureLiteralEmitter.extractSwiftFixtureCandidate(
                from: "noise\n\(markedCandidate)\nmore noise"
            ) == candidate
        )
        #expect(
            ElectronCashTranscriptCaptureLiteralEmitter.extractSwiftFixtureCandidate(
                from: candidate
            ) == nil
        )
    }
}
