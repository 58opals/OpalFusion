// RoundEngineScriptedValidator+ValidationGroup4.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
    @Test("Round engine rejects shared components before local covert submission")
    func validateSharedComponentsBeforeCovertSubmissionFails() {
        var engine = Self.makeEngine()
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")

        Self.driveThroughStartRound(engine: &engine)
        _ = engine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_031)
        )
        _ = engine.apply(
            input: .primaryMessage(.blindSignatureResponses(Self.blindSignatureResponses)),
            now: Self.instant(1_032)
        )
        _ = engine.apply(
            input: .primaryMessage(.allCommitments(Self.allCommitments)),
            now: Self.instant(1_034)
        )

        let sharedEffects = engine.apply(
            input: .primaryMessage(.shareCovertComponents(Self.sharedComponents)),
            now: Self.instant(1_034)
        )

        #expect(engine.clientState.round?.completionStatus == .protocolIncompatible)
        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(
            sharedEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Shared components arrived out of order",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects covert acknowledgements before local covert submission")
    func validateCovertAcknowledgementBeforeSubmissionFails() {
        var engine = Self.makeEngine()
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")

        Self.driveThroughStartRound(engine: &engine)
        _ = engine.apply(
            input: .participantReservationLoaded(Self.participantReservation),
            now: Self.instant(1_031)
        )
        _ = engine.apply(
            input: .primaryMessage(.blindSignatureResponses(Self.blindSignatureResponses)),
            now: Self.instant(1_032)
        )
        _ = engine.apply(
            input: .primaryMessage(.allCommitments(Self.allCommitments)),
            now: Self.instant(1_034)
        )

        let acknowledgementEffects = engine.apply(
            input: .covertResponse(.acknowledgement(.init())),
            now: Self.instant(1_034)
        )

        #expect(engine.clientState.round?.completionStatus == .protocolIncompatible)
        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(
            acknowledgementEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Covert acknowledgement arrived out of order",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects late finalized transactions before signature extraction")
    func validateLateFinalizedTransactionDoesNotBuildSignatures() {
        var engine = OpalFusion.Execution.RoundEngine(
            configuration: Self.configuration,
            genesisHash: [0xAA, 0xBB, 0xCC],
            joinPools: Self.joinPools,
            workflow: .init(
                buildPlayerCommit: { _ in Self.playerCommit },
                buildCovertComponentMessages: { _ in [Self.covertComponentMessage] },
                buildTransactionFinalizationProposal: { _ in Self.transactionProposal },
                buildCovertSignatureMessages: { _ in
                    Issue.record("Signature messages must not be built after the signature deadline")
                    return [Self.signatureMessage]
                },
                buildMyProofsList: { _ in Self.myProofsList },
                buildBlames: { _ in Self.blames }
            )
        )
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")

        Self.driveToSharedComponents(engine: &engine)

        let finalizedEffects = engine.apply(
            input: .finalizedTransactionLoaded(Self.finalizedTransaction),
            now: Self.instant(1_061)
        )

        #expect(engine.clientState.round?.completionStatus == .transportFailed)
        #expect(engine.session.lastError == .transportUnavailable)
        #expect(
            finalizedEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Signature deadline elapsed before submission",
                        isTerminal: true
                    )
                )
            ]
        )
    }
}
