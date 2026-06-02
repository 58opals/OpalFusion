// LiveRuntimeDriverValidator+ValidationGroup3.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

extension LiveRuntimeDriverValidator {
    @Test("Live runtime driver rejects invalid join-pool requests before transport connect")
    func validateJoinPoolStartupValidation() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: .init(tiers: [], tags: []),
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
        #expect(snapshot.lastErrorSummary == "Join pool tiers must not be empty")
        #expect(snapshot.clientState.isConnected == false)
        #expect(await primaryTransport.recordedConnectCallCount == 0)

        #expect(
            OpalFusion.Runtime.validateStartupConfiguration(
                PrimaryRuntimeTestFixtures.configuration,
                genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
                joinPools: .init(tiers: [0], tags: [])
            ) == "Join pool tiers must be greater than zero"
        )
        #expect(
            OpalFusion.Runtime.validateStartupConfiguration(
                PrimaryRuntimeTestFixtures.configuration,
                genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
                joinPools: .init(
                    tiers: [
                        OpalFusion.Execution.ProtocolPrimitives.maximumMoneySatoshis + 1
                    ],
                    tags: []
                )
            ) == "Join pool tiers must not exceed the maximum BCH money supply"
        )
        #expect(
            OpalFusion.Runtime.validateStartupConfiguration(
                PrimaryRuntimeTestFixtures.configuration,
                genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
                joinPools: .init(tiers: [10_000, 10_000], tags: [])
            ) == "Join pool tiers must not contain duplicates"
        )
        #expect(
            OpalFusion.Runtime.validateStartupConfiguration(
                PrimaryRuntimeTestFixtures.configuration,
                genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
                joinPools: .init(
                    tiers: [10_000],
                    tags: [.init(identifier: [], limit: 1)]
                )
            ) == "Join pool tags must include an identifier"
        )
        #expect(
            OpalFusion.Runtime.validateStartupConfiguration(
                PrimaryRuntimeTestFixtures.configuration,
                genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
                joinPools: .init(
                    tiers: [10_000],
                    tags: [.init(identifier: [0x01], limit: 0)]
                )
            ) == "Join pool tag limits must be greater than zero"
        )
    }

    @Test("Live runtime driver rejects duplicate join-pool tag identifiers before transport connect")
    func validateDuplicateJoinPoolTagStartupValidation() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let duplicateTag = OpalFusion.ProtocolModel.PoolTag(
            identifier: [0x01, 0x02],
            limit: 1
        )
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: .init(
                tiers: [10_000],
                tags: [
                    duplicateTag,
                    .init(identifier: duplicateTag.identifier, limit: 2)
                ]
            ),
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
        #expect(snapshot.lastErrorSummary == "Join pool tags must not contain duplicate identifiers")
        #expect(snapshot.clientState.isConnected == false)
        #expect(await primaryTransport.recordedConnectCallCount == 0)
    }

    @Test("Live runtime driver rejects oversized join-pool tag sets before transport connect")
    func validateOversizedJoinPoolTagStartupValidation() async throws {
        let primaryTransport = ScriptedPrimaryTransport()
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: .init(
                tiers: [10_000],
                tags: (0 ..< 6).map { index in
                    .init(identifier: [UInt8(index + 1)], limit: 1)
                }
            ),
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
        #expect(snapshot.lastErrorSummary == "Join pool tags must not exceed five entries")
        #expect(snapshot.clientState.isConnected == false)
        #expect(await primaryTransport.recordedConnectCallCount == 0)
    }
}
