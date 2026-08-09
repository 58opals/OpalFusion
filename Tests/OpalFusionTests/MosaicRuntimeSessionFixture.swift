// MosaicRuntimeSessionFixture.swift

@testable import OpalFusion

struct MosaicRuntimeSessionFixture: Sendable {
    var session: OpalFusion.Mosaic.RuntimeSession
    let roster: OpalFusion.Mosaic.Attempt.Roster
    let attemptIdentifier: OpalFusion.Mosaic.LocalAttempt.AttemptIdentifier
    let generationIdentifier: OpalFusion.Mosaic.LocalAttempt.GenerationIdentifier
    let materialIdentifier: OpalFusion.Mosaic.LocalAttempt.MaterialIdentifier
    let manifest: OpalFusion.Mosaic.Attempt.ManifestBinding
    let transactionPreparation:
        MosaicUnsignedTransactionTranscriptFixtures.Prepared
}
