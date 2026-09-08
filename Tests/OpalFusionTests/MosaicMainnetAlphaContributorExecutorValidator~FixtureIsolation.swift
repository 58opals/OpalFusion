// MosaicMainnetAlphaContributorExecutorValidator~FixtureIsolation.swift

import Testing
@testable import OpalFusion

extension MosaicMainnetAlphaContributorExecutorValidator {
    @Test("Prepared material never shares mutable sessions or admission ledgers")
    func isolateMutableExecutionState() async throws {
        let first = try await MosaicMainnetAlphaExecutionFixtures.prepare()
        var cancelledSession = first.session
        var cancelledLedger = first.admission.ledger
        _ = cancelledSession.apply(input: .cancel)
        _ = cancelledLedger.apply(input: .cancel)

        let second = try await MosaicMainnetAlphaExecutionFixtures.prepare()
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
