// PrimaryRuntimeSessionValidator+ValidationGroup1.swift

@testable import OpalFusion
import Testing

extension PrimaryRuntimeSessionValidator {
    @Test("Primary runtime writes framed ClientHello and JoinPools during handshake")
    func validateHandshakeFlow() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()

        let connectEffects = session.apply(
            input: .connected,
            now: PrimaryRuntimeTestFixtures.instant(995)
        )
        #expect(connectEffects.count == 2)
        let connectWriteEffect = try #require(connectEffects.first)
        #expect(
            try PrimaryRuntimeTestFixtures.extractWriteMessage(from: connectWriteEffect)
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )
        let connectEventEffect = try #require(connectEffects.dropFirst().first)
        #expect(
            connectEventEffect == .emitHostEvent(
                roundIdentifier: nil,
                event: .init(
                    kind: .status,
                    phase: .connecting,
                    summary: "Primary channel connected; sending ClientHello"
                )
            )
        )

        let helloEffects = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .serverHello(PrimaryRuntimeTestFixtures.serverHello)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(996)
        )
        #expect(helloEffects.count == 2)
        let helloWriteEffect = try #require(helloEffects.first)
        #expect(
            try PrimaryRuntimeTestFixtures.extractWriteMessage(from: helloWriteEffect)
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )
        let helloEventEffect = try #require(helloEffects.dropFirst().first)
        #expect(
            helloEventEffect == .emitHostEvent(
                roundIdentifier: nil,
                event: .init(
                    kind: .status,
                    phase: .connecting,
                    summary: "ServerHello received; joining eligible pools"
                )
            )
        )
        #expect(session.clientState.isConnected)
        #expect(session.clientState.round == nil)
    }

    @Test("Primary runtime triggers covert preparation during FusionBegin warmup")
    func validateWarmupPreparation() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        _ = session.apply(input: .connected, now: PrimaryRuntimeTestFixtures.instant(995))
        _ = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .serverHello(PrimaryRuntimeTestFixtures.serverHello)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(996)
        )

        let effects = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )

        #expect(
            effects == [
                .prepareCovertEndpoint(
                    plan: PrimaryRuntimeTestFixtures.expectedPreparationPlan(startedAt: 1_000)
                ),
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .status,
                        phase: .connecting,
                        summary: "Fusion warmup started"
                    )
                )
            ]
        )
        #expect(session.covertSession.substate == .preparing)
        #expect(session.covertSession.endpointContext == PrimaryRuntimeTestFixtures.covertEndpointContext)
    }

    @Test("Primary runtime keeps ServerHello context when the primary channel disconnects before FusionBegin")
    func validateDisconnectAfterServerHelloBeforeFusionBegin() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        _ = session.apply(input: .connected, now: PrimaryRuntimeTestFixtures.instant(995))
        _ = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .serverHello(PrimaryRuntimeTestFixtures.serverHello)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(996)
        )

        let effects = session.apply(
            input: .disconnected,
            now: PrimaryRuntimeTestFixtures.instant(997)
        )

        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "Primary channel disconnected"
                    )
                )
            ]
        )
        #expect(session.engine.session.latestServerHello == PrimaryRuntimeTestFixtures.serverHello)
        #expect(session.clientState.round == nil)
        #expect(session.lastError == .transportUnavailable)
        #expect(session.lastErrorSummary == "Primary channel disconnected")
    }
}
