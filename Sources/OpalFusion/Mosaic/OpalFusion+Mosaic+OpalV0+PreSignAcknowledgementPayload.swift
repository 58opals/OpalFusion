// OpalFusion+Mosaic+OpalV0+PreSignAcknowledgementPayload.swift

extension OpalFusion.Mosaic.OpalV0 {
    struct PreSignAcknowledgementPayload: Sendable, Equatable {
        let roundIdentifier: [UInt8]
        let transcriptRoot: [UInt8]

        init(roundIdentifier: [UInt8], transcriptRoot: [UInt8]) throws {
            guard roundIdentifier.count == OpalFusion.Mosaic.OpalV0.digestByteCount else {
                throw WireContractError.invalidRoundIdentifierLength(
                    actual: roundIdentifier.count
                )
            }
            guard transcriptRoot.count == OpalFusion.Mosaic.OpalV0.digestByteCount else {
                throw WireContractError.invalidTranscriptRootLength(
                    actual: transcriptRoot.count
                )
            }
            self.roundIdentifier = Array(roundIdentifier)
            self.transcriptRoot = Array(transcriptRoot)
        }
    }
}
