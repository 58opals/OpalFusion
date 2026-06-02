// LiveRuntimeDriverValidator+ValidationGroup6.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

extension LiveRuntimeDriverValidator {
    @Test("Live runtime driver stops queued handshake effects after a primary write failure")
    func validatePrimaryWriteFailureDoesNotEmitQueuedHandshakeStatus() async throws {
        let primaryTransport = ScriptedPrimaryTransport(
            writeError: NSError(domain: "LiveRuntimeDriverValidator", code: 2)
        )
        let eventSink = RecordedHostEventSink()
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            participantReservationSource: DelayedParticipantReservationSource(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: DelayedTransactionAssembler(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            hostEventSink: { roundIdentifier, event in
                await eventSink.record(
                    roundIdentifier: roundIdentifier,
                    event: event
                )
            },
            primaryTransport: primaryTransport,
            covertTransport: ScriptedCovertTransport()
        )

        await driver.start()

        let snapshot = await driver.currentSnapshot
        #expect(snapshot.lastError == .transportUnavailable)
        #expect(snapshot.lastErrorSummary == "Primary write failed")

        let events = await eventSink.recordedSnapshots
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.roundIdentifier == nil)
        #expect(event.event.kind == .failure)
        #expect(event.event.summary == "Primary write failed")
        #expect(events.contains { $0.event.summary == "Primary channel connected; sending ClientHello" } == false)
    }

    @Test("Live runtime driver uses a TLS-required coordinator when configuration opts in")
    func validateTLSRequiredCoordinatorPath() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start(requiresTLS: true)
        let covertTransport = ScriptedCovertTransport()
        let eventSink = RecordedHostEventSink()
        let observedRequiresTLS = MutableBoolState()
        let tlsTrustAnchorCertificateDERs = try await LoopbackPrimaryTLSTestFixture
            .loadTrustAnchorCertificateDERs()
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: .init(
                coordinatorHost: LoopbackPrimaryTLSTestFixture.host,
                coordinatorPort: await coordinator.port,
                coordinatorRequiresTLS: true,
                covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
            ),
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            participantReservationSource: DelayedParticipantReservationSource(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: DelayedTransactionAssembler(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            hostEventSink: { roundIdentifier, event in
                await eventSink.record(
                    roundIdentifier: roundIdentifier,
                    event: event
                )
            },
            primaryTransportFactory: { configuration in
                await observedRequiresTLS.update(configuration.coordinatorRequiresTLS)
                return OpalFusion.Runtime.LivePrimaryTransport(
                    host: configuration.coordinatorHost,
                    port: configuration.coordinatorPort,
                    requiresTLS: configuration.coordinatorRequiresTLS,
                    tlsTrustAnchorCertificateDERs: tlsTrustAnchorCertificateDERs
                )
            },
            covertTransport: covertTransport
        )

        await driver.start()
        #expect(
            try await coordinator.readNextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        #expect(
            try await coordinator.readNextClientMessage()
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        let snapshot = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await driver.currentSnapshot
                if snapshot.clientState.isConnected {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        #expect(snapshot.lastError == nil)
        #expect(snapshot.lastErrorSummary == nil)
        #expect(await observedRequiresTLS.value == true)

        let events = await eventSink.recordedSnapshots
        #expect(events.contains { $0.event.summary == "Primary channel connected; sending ClientHello" })

        await driver.stop()
        await coordinator.stop()
    }
}
