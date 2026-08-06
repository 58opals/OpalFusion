// FusionFacadeScaffoldValidator.swift

import OpalFusion
import Testing

struct FusionFacadeScaffoldValidator {
    @Test("Engine registry distinguishes CashFusion from Mosaic")
    func validateEngineRegistry() {
        #expect(OpalFusion.Engine.allCases == [.cashFusion, .mosaic])
        #expect(Self.requireSendable(OpalFusion.Engine.mosaic) == .mosaic)
    }

    @Test("CashFusion configuration aggregates the live client inputs")
    func validateCashFusionConfiguration() {
        let coordinator = Self.makeCoordinatorConfiguration()
        let joinPools = Self.makeJoinPools()
        let configuration = OpalFusion.CashFusion.Configuration(
            coordinator: coordinator,
            genesisHash: [0xAA, 0xBB],
            joinPools: joinPools,
            reconnectPolicy: .walletDefault
        )

        #expect(configuration.coordinator == coordinator)
        #expect(configuration.genesisHash == [0xAA, 0xBB])
        #expect(configuration.joinPools == joinPools)
        #expect(configuration.reconnectPolicy == .walletDefault)
        #expect(Self.requireSendable(configuration) == configuration)
    }

    @Test("Mosaic draft profile exposes protocol constants without a live runtime claim")
    func validateMosaicDraftProfile() {
        let configuration = OpalFusion.Mosaic.Configuration()
        let roster = configuration.rosterPolicy

        #expect(configuration.protocolVersion.rawValue == "Mosaic/1-draft.1")
        #expect(configuration.transportProfile.rawValue == "nostr-tor/1-draft.1")
        #expect(roster.minimumContributorCount == 6)
        #expect(roster.targetContributorCount == 8)
        #expect(roster.conductorCount == 1)
        #expect(roster.minimumCandidateCount == 7)
        #expect(roster.targetCandidateCount == 9)
        #expect(roster.maximumCandidateCount == 9)
        #expect(roster.componentCountPerContributor == 23)
        #expect(OpalFusion.Mosaic.Role.allCases == [.conductor, .contributor])
        #expect(Self.requireSendable(configuration) == configuration)
    }

    @Test("Automatic mode preserves candidate order and an explicit fallback boundary")
    func validateAutomaticMode() throws {
        let cashFusion = OpalFusion.CashFusion.Configuration(
            coordinator: Self.makeCoordinatorConfiguration(),
            joinPools: Self.makeJoinPools()
        )
        let mosaic = OpalFusion.Mosaic.Configuration()
        let automatic = try OpalFusion.Session.AutomaticConfiguration(
            candidates: [
                .mosaic(mosaic),
                .cashFusion(cashFusion),
            ],
            fallbackPolicy: .beforeReservationOnly
        )
        let mode = OpalFusion.Session.Mode.automatic(automatic)
        let cashFusionMode = OpalFusion.Session.Mode.cashFusion(cashFusion)
        let mosaicMode = OpalFusion.Session.Mode.mosaic(mosaic)

        #expect(automatic.preferredEngine == .mosaic)
        #expect(automatic.fallbackPolicy == .beforeReservationOnly)
        #expect(mode.preferredEngine == .mosaic)
        #expect(mode.configuredEngines == [.mosaic, .cashFusion])
        #expect(cashFusionMode.configuredEngines == [.cashFusion])
        #expect(mosaicMode.configuredEngines == [.mosaic])
        #expect(Self.requireSendable(mode) == mode)
    }

    @Test("Automatic mode rejects empty and duplicate engine candidates")
    func validateAutomaticModeInvariants() {
        let noCandidatesError = OpalFusion.Session.AutomaticConfiguration.ValidationError.noCandidates
        #expect(throws: noCandidatesError) {
            _ = try OpalFusion.Session.AutomaticConfiguration(
                candidates: [],
                fallbackPolicy: .disabled
            )
        }

        let mosaic = OpalFusion.Mosaic.Configuration()
        let duplicateEngineError = OpalFusion.Session.AutomaticConfiguration.ValidationError
            .duplicateEngine(.mosaic)
        #expect(throws: duplicateEngineError) {
            _ = try OpalFusion.Session.AutomaticConfiguration(
                candidates: [.mosaic(mosaic), .mosaic(mosaic)],
                fallbackPolicy: .beforeReservationOnly
            )
        }
    }

    private static func makeCoordinatorConfiguration() -> OpalFusion.Client.Configuration {
        .init(
            coordinatorHost: "fusion.example",
            coordinatorPort: 8788,
            covertChannel: .init(
                entryPath: "/fusion",
                maxPayloadBytes: 1024,
                requestTimeoutMilliseconds: 5_000
            )
        )
    }

    private static func makeJoinPools() -> OpalFusion.ProtocolModel.JoinPools {
        .init(tiers: [100_000], tags: [])
    }

    private static func requireSendable<Value: Sendable>(_ value: Value) -> Value {
        value
    }
}
