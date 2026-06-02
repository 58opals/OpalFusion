// PrimaryRuntimeSessionValidator+ValidationGroup4.swift

@testable import OpalFusion
import Testing

extension PrimaryRuntimeSessionValidator {
    @Test("Primary runtime maps unsupported execution materialization to not implemented")
    func validateUnsupportedExecutionMaterializationProjection() throws {
        let unsupportedSummary = "OpalCrypto-backed execution materialization is not wired yet"
        let workflow = OpalFusion.Execution.WorkflowContext(
            buildPlayerCommit: { _ in
                throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(unsupportedSummary)
            },
            buildCovertComponentMessages: { _ in
                throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(unsupportedSummary)
            },
            buildTransactionFinalizationProposal: { _ in
                throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(unsupportedSummary)
            },
            buildCovertSignatureMessages: { _ in
                throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(unsupportedSummary)
            },
            buildMyProofsList: { _ in
                throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(unsupportedSummary)
            },
            buildBlames: { _ in
                throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(unsupportedSummary)
            }
        )
        var session = OpalFusion.Runtime.PrimaryRuntimeSession(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: workflow,
            baseline: PrimaryRuntimeTestFixtures.baseline
        )
        try PrimaryRuntimeTestFixtures.driveThroughWarmup(session: &session)
        _ = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .startRound(PrimaryRuntimeTestFixtures.startRound)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_030)
        )

        let effects = session.apply(
            input: .participantReservationLoaded(
                PrimaryRuntimeTestFixtures.participantReservation
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_031)
        )

        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: unsupportedSummary,
                        isTerminal: true
                    )
                )
            ]
        )
        #expect(session.lastError == .notImplemented)
        #expect(session.lastErrorSummary == unsupportedSummary)
        #expect(
            session.clientState.round == .init(
                identifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                completionStatus: .hostRejected
            )
        )
    }

    @Test("Primary runtime fails unsupported finalized transactions when the host transaction is loaded")
    func validateUnsupportedFinalizedTransactionFailsEarly() throws {
        let unsupportedSummary = OpalFusion.Execution.ProtocolPrimitives.supportedUnlockingScriptSummary
        let workflow = OpalFusion.Execution.WorkflowContext(
            buildPlayerCommit: { _ in PrimaryRuntimeTestFixtures.playerCommit },
            buildCovertComponentMessages: { _ in [PrimaryRuntimeTestFixtures.covertComponentMessage] },
            buildTransactionFinalizationProposal: { _ in PrimaryRuntimeTestFixtures.transactionProposal },
            buildCovertSignatureMessages: { _ in
                throw OpalFusion.Execution.WorkflowFailure.unsupportedExecution(unsupportedSummary)
            },
            buildMyProofsList: { _ in PrimaryRuntimeTestFixtures.myProofsList },
            buildBlames: { _ in PrimaryRuntimeTestFixtures.blames }
        )
        var session = OpalFusion.Runtime.PrimaryRuntimeSession(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: workflow,
            baseline: PrimaryRuntimeTestFixtures.baseline
        )
        try PrimaryRuntimeTestFixtures.driveToAwaitingSharedComponents(session: &session)
        _ = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_040)
        )

        let effects = session.apply(
            input: .finalizedTransactionLoaded(PrimaryRuntimeTestFixtures.finalizedTransaction),
            now: PrimaryRuntimeTestFixtures.instant(1_042)
        )

        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: unsupportedSummary,
                        isTerminal: true
                    )
                )
            ]
        )
        #expect(session.lastError == .notImplemented)
        #expect(session.lastErrorSummary == unsupportedSummary)
        #expect(session.clientState.round?.completionStatus == .hostRejected)
    }

    @Test("Primary runtime maps transaction assembly finalization failures")
    func validateTransactionAssemblyFinalizationFailureMapping() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveToAwaitingSharedComponents(session: &session)
        _ = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_040)
        )
        let summary = "Assembler could not produce a finalized transaction"

        let effects = session.apply(
            input: .transactionFinalizationRejected(
                .transactionAssemblyFailed(summary: summary)
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_042)
        )

        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: summary,
                        isTerminal: true
                    )
                )
            ]
        )
        #expect(session.lastError == .notImplemented)
        #expect(session.lastErrorSummary == summary)
        #expect(session.clientState.round?.completionStatus == .hostRejected)
    }
}
