// OpalFusion+Mosaic+OpalMainnetAlpha+PreSignAcknowledgement.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// A contributor's inner signature over the exact transcript acknowledgement document.
    ///
    /// The surrounding control envelope authenticates delivery metadata separately; its signature
    /// is never reused as this protocol acknowledgement signature.
    struct PreSignAcknowledgementSubmission: Sendable, Equatable {
        let acknowledgement: OpalFusion.Mosaic.Attempt.TranscriptAcknowledgement
        let validation: OpalFusion.Mosaic.Attempt
            .TranscriptAcknowledgementValidation
        let canonicalBytes: [UInt8]

        init(
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            roundIdentifier: [UInt8],
            transcriptRoot: [UInt8],
            signature: [UInt8]
        ) throws {
            let acknowledgement = OpalFusion.Mosaic.Attempt
                .TranscriptAcknowledgement(
                    contributor: contributor,
                    roundIdentifier: roundIdentifier,
                    transcriptRoot: transcriptRoot,
                    rawRepresentation: signature
                )
            let validation: OpalFusion.Mosaic.Attempt
                .TranscriptAcknowledgementValidation
            do {
                validation = try .init(
                    validating: acknowledgement,
                    profile: .opalMainnetAlpha
                )
            } catch {
                throw ContractError.invalidControlSignature
            }
            let canonicalBytes = try CanonicalWireCodec
                .encodePreSignAcknowledgementSubmission(
                    roundIdentifier: roundIdentifier,
                    transcriptRoot: transcriptRoot,
                    signature: signature
                )
            self.acknowledgement = acknowledgement
            self.validation = validation
            self.canonicalBytes = canonicalBytes
        }
    }
}
