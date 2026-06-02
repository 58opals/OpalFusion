// LiveRuntimeDriverValidator+ValidationGroup2.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

extension LiveRuntimeDriverValidator {
    @Test("Runtime configuration rejects covert entry paths with surrounding whitespace")
    func validateCovertEntryPathWithSurroundingWhitespace() {
        let baseConfiguration = PrimaryRuntimeTestFixtures.configuration
        let paddedPathConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: baseConfiguration.coordinatorHost,
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: .init(
                entryPath: "\(baseConfiguration.covertChannel.entryPath) ",
                maxPayloadBytes: baseConfiguration.covertChannel.maxPayloadBytes,
                requestTimeoutMilliseconds: baseConfiguration.covertChannel.requestTimeoutMilliseconds
            )
        )

        #expect(
            OpalFusion.Runtime.validateConfiguration(paddedPathConfiguration) ==
                "Covert entry path must not include leading or trailing whitespace"
        )
    }

    @Test("Runtime configuration rejects covert entry paths with internal whitespace")
    func validateCovertEntryPathWithInternalWhitespace() {
        let baseConfiguration = PrimaryRuntimeTestFixtures.configuration
        let whitespacePathConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: baseConfiguration.coordinatorHost,
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: .init(
                entryPath: "/fusion path",
                maxPayloadBytes: baseConfiguration.covertChannel.maxPayloadBytes,
                requestTimeoutMilliseconds: baseConfiguration.covertChannel.requestTimeoutMilliseconds
            )
        )

        #expect(
            OpalFusion.Runtime.validateConfiguration(whitespacePathConfiguration) ==
                "Covert entry path must not include whitespace"
        )
    }

    @Test("Runtime configuration rejects covert entry paths with query or fragment delimiters")
    func validateCovertEntryPathWithQueryOrFragmentDelimiter() {
        let baseConfiguration = PrimaryRuntimeTestFixtures.configuration
        let queryPathConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: baseConfiguration.coordinatorHost,
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: .init(
                entryPath: "\(baseConfiguration.covertChannel.entryPath)?round=1",
                maxPayloadBytes: baseConfiguration.covertChannel.maxPayloadBytes,
                requestTimeoutMilliseconds: baseConfiguration.covertChannel.requestTimeoutMilliseconds
            )
        )
        #expect(
            OpalFusion.Runtime.validateConfiguration(queryPathConfiguration) ==
                "Covert entry path must not include query or fragment delimiters"
        )

        let fragmentPathConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: baseConfiguration.coordinatorHost,
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: .init(
                entryPath: "\(baseConfiguration.covertChannel.entryPath)#round",
                maxPayloadBytes: baseConfiguration.covertChannel.maxPayloadBytes,
                requestTimeoutMilliseconds: baseConfiguration.covertChannel.requestTimeoutMilliseconds
            )
        )
        #expect(
            OpalFusion.Runtime.validateConfiguration(fragmentPathConfiguration) ==
                "Covert entry path must not include query or fragment delimiters"
        )
    }

    @Test("Runtime configuration rejects covert request timeouts outside Duration range")
    func validateCovertRequestTimeoutRange() {
        let baseConfiguration = PrimaryRuntimeTestFixtures.configuration
        let oversizedTimeoutConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: baseConfiguration.coordinatorHost,
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: .init(
                entryPath: baseConfiguration.covertChannel.entryPath,
                maxPayloadBytes: baseConfiguration.covertChannel.maxPayloadBytes,
                requestTimeoutMilliseconds: UInt64(Int64.max) + 1
            )
        )

        #expect(
            OpalFusion.Runtime.validateConfiguration(oversizedTimeoutConfiguration) ==
                "Covert request timeout must fit the supported duration range"
        )
    }

    @Test("Live runtime driver rejects invalid startup configuration before transport connect")
    func validateInvalidConfiguration() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let covertTransport = ScriptedCovertTransport()
        let eventSink = RecordedHostEventSink()
        let participantReservationSource = DelayedParticipantReservationSource(
            participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
        )
        let transactionAssembler = DelayedTransactionAssembler(
            finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
        )

        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: .init(
                coordinatorHost: "",
                coordinatorPort: PrimaryRuntimeTestFixtures.configuration.coordinatorPort,
                covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
            ),
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            participantReservationSource: participantReservationSource,
            transactionAssembler: transactionAssembler,
            hostEventSink: { roundIdentifier, event in
                await eventSink.record(
                    roundIdentifier: roundIdentifier,
                    event: event
                )
            },
            primaryTransport: primaryTransport,
            covertTransport: covertTransport
        )

        await driver.start()

        let snapshot = await driver.currentSnapshot
        #expect(snapshot.lastError == .invalidConfiguration)
        #expect(snapshot.lastErrorSummary == "Coordinator host must not be empty")
        #expect(snapshot.clientState.isConnected == false)
        #expect(await primaryTransport.recordedConnectCallCount == 0)

        let events = await eventSink.recordedSnapshots
        #expect(
            events == [
                .init(
                    roundIdentifier: nil,
                    event: .init(
                        kind: .failure,
                        phase: .connecting,
                        summary: "Coordinator host must not be empty"
                    )
                )
            ]
        )
    }

    @Test("Live runtime driver rejects invalid genesis hashes before transport connect")
    func validateGenesisHashStartupValidation() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: [0x00],
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            participantReservationSource: DelayedParticipantReservationSource(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            transactionAssembler: DelayedTransactionAssembler(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            primaryTransport: primaryTransport,
            covertTransport: ScriptedCovertTransport()
        )

        await driver.start()

        let snapshot = await driver.currentSnapshot
        #expect(snapshot.lastError == .invalidConfiguration)
        #expect(snapshot.lastErrorSummary == "Genesis hash must be 32 bytes")
        #expect(snapshot.clientState.isConnected == false)
        #expect(await primaryTransport.recordedConnectCallCount == 0)
    }
}
