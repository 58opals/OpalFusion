// ElectronCashTranscriptCapture.swift

struct ElectronCashTranscriptCapture: Sendable, Equatable {
    let primaryInboundChunks: [[UInt8]]
    let primaryOutboundChunks: [[UInt8]]
    let covertRequestPayloads: [[UInt8]]
    let covertResponsePayloads: [[UInt8]]
    let clientMessageKinds: [String]
    let serverMessageKinds: [String]
    let covertMessageKinds: [String]
    let covertResponseKinds: [String]
    let roundOutcomes: [String]
    let eventSummaries: [String]

    init(
        primaryInboundChunks: [[UInt8]],
        primaryOutboundChunks: [[UInt8]],
        covertRequestPayloads: [[UInt8]],
        covertResponsePayloads: [[UInt8]],
        clientMessageKinds: [String],
        serverMessageKinds: [String],
        covertMessageKinds: [String],
        covertResponseKinds: [String],
        roundOutcomes: [String],
        eventSummaries: [String]
    ) {
        self.primaryInboundChunks = primaryInboundChunks
        self.primaryOutboundChunks = primaryOutboundChunks
        self.covertRequestPayloads = covertRequestPayloads
        self.covertResponsePayloads = covertResponsePayloads
        self.clientMessageKinds = clientMessageKinds
        self.serverMessageKinds = serverMessageKinds
        self.covertMessageKinds = covertMessageKinds
        self.covertResponseKinds = covertResponseKinds
        self.roundOutcomes = roundOutcomes
        self.eventSummaries = eventSummaries
    }
}
