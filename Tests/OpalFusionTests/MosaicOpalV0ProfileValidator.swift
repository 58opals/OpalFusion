// MosaicOpalV0ProfileValidator.swift

import OpalFusion
import Testing

@Suite("Mosaic Opal v0 profile")
struct MosaicOpalV0ProfileValidator {
    @Test("Configuration derives every contract from one profile")
    func deriveEveryContractFromOneProfile() {
        let configuration = OpalFusion.Mosaic.Configuration(profile: .opalV0)

        #expect(configuration.profile.rawValue == "Mosaic/0-opal.1")
        #expect(configuration.protocolVersion == .opalV0)
        #expect(configuration.transportProfile == .nostrConformanceOpalV0)
        #expect(configuration.rosterPolicy == .opalV0)
        #expect(
            configuration.profile.transactionProfileIdentifier
                == "bch-chipnet-p2pkh-schnorr/0-opal.1"
        )
        #expect(configuration.profile.networkGenesisHash?.count == 32)
    }

    @Test("Freeze the Opal v0 roster")
    func freezeOpalV0Roster() {
        let roster = OpalFusion.Mosaic.Profile.opalV0.rosterPolicy

        #expect(roster.conductorCount == 1)
        #expect(roster.minimumContributorCount == 6)
        #expect(roster.targetContributorCount == 8)
        #expect(roster.minimumCandidateCount == 7)
        #expect(roster.targetCandidateCount == 9)
        #expect(roster.maximumCandidateCount == 9)
        #expect(roster.componentCountPerContributor == 23)
    }

    @Test("Preserve the draft configuration as the source-compatible default")
    func preserveDraftDefault() {
        let configuration = OpalFusion.Mosaic.Configuration()

        #expect(configuration.profile == .draft1)
        #expect(configuration.protocolVersion == .draft1)
        #expect(configuration.transportProfile == .nostrTorDraft1)
        #expect(configuration.rosterPolicy == .draft1)
    }
}
