// MosaicMainnetAlphaContributorExecutorValidator~FixtureIsolation.swift

import Testing
@testable import MosaicEngine
@testable import OpalFusionCore
extension MosaicMainnetAlphaContributorExecutorValidator {
    @Test("Prepared material never shares mutable sessions or admission ledgers")
    func isolateMutableExecutionState() async throws {
        let clock = ContinuousClock()
        let firstStart = clock.now
        let first = try await MosaicMainnetAlphaExecutionFixtures.prepare()
        let firstDuration = firstStart.duration(to: clock.now)
        var cancelledSession = first.session
        var cancelledLedger = first.admission.ledger
        _ = cancelledSession.apply(input: .cancel)
        _ = cancelledLedger.apply(input: .cancel)

        let repeatedStart = clock.now
        let second = try await MosaicMainnetAlphaExecutionFixtures.prepare()
        let repeatedDuration = repeatedStart.duration(to: clock.now)
        let referenceStart = clock.now
        let reference = try Fixture.makeHarness(
            localRole: .contributor,
            verificationKey: ExecutionFixture.require(
                MosaicMainnetAlphaFixtures.authorizationEvaluator()
                    .verificationKey
            ),
            bchSignatureVerificationKey: ExecutionFixture.require(
                MosaicMainnetAlphaFixtures.bchSignatureAuthorizationEvaluator()
                    .verificationKey
            )
        )
        let referenceDuration = referenceStart.duration(to: clock.now)
        let referenceSession = try Alpha.RuntimeSession(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: reference.election
            ),
            attemptIdentifier: reference.attemptIdentifier,
            generationIdentifier: reference.generationIdentifier,
            materialIdentifier: reference.materialIdentifier,
            localControlIdentity: reference.localControlIdentity,
            proposalValidation: reference.proposalValidation
        )

        // Suite initialization acquires both authorization evaluators before
        // these intervals. Only the first prepare pays uncached material work.
        print("Execution fixture first prepare: \(firstDuration)")
        print("Execution fixture repeated prepare: \(repeatedDuration)")
        print("Execution fixture fresh admission oracle: \(referenceDuration)")
        for prepared in [first, second] {
            #expect(prepared.admission.election.result == reference.election.result)
            #expect(prepared.admission.manifest == reference.manifest)
            #expect(
                prepared.admission.proposalValidation
                    == reference.proposalValidation
            )
            #expect(
                prepared.admission.attemptIdentifier
                    == reference.attemptIdentifier
            )
            #expect(
                prepared.admission.generationIdentifier
                    == reference.generationIdentifier
            )
            #expect(
                prepared.admission.materialIdentifier
                    == reference.materialIdentifier
            )
            #expect(
                prepared.admission.localControlIdentity
                    == reference.localControlIdentity
            )
            #expect(prepared.session.context == referenceSession.context)
        }
        #expect(second.session.state == .active(.manifestAgreement))
        #expect(second.admission.ledger.state == .active(.manifestAgreement))
        #expect(cancelledSession.state != second.session.state)
        #expect(cancelledLedger.state != second.admission.ledger.state)
        #expect(first.materialized.prepared == second.materialized.prepared)
        #expect(
            first.localMaterial.playerCommit
                == second.localMaterial.playerCommit
        )
    }
}
