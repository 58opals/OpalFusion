// MosaicRuntimeSessionFixture.swift

@testable import OpalFusion

struct MosaicRuntimeSessionFixture {
    var session: OpalFusion.Mosaic.RuntimeSession
    let roster: OpalFusion.Mosaic.Attempt.Roster
    let attemptIdentifier: OpalFusion.Mosaic.LocalAttempt.AttemptIdentifier
    let generationIdentifier: OpalFusion.Mosaic.LocalAttempt.GenerationIdentifier
    let manifest: OpalFusion.Mosaic.Attempt.ManifestBinding
}
