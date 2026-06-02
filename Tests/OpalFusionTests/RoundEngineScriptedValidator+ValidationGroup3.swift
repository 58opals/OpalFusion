// RoundEngineScriptedValidator+ValidationGroup3.swift

@testable import OpalFusion
import Testing

extension RoundEngineScriptedValidator {
    @Test("Round engine validates shared components even when signatures are skipped")
    func validateSkipSignaturesStillValidatesSharedComponents() {
        var engine = OpalFusion.Execution.RoundEngine(
            configuration: Self.configuration,
            genesisHash: [0xAA, 0xBB, 0xCC],
            joinPools: Self.joinPools,
            workflow: .init(
                buildPlayerCommit: { _ in Self.playerCommit },
                buildCovertComponentMessages: { _ in [Self.covertComponentMessage] },
                buildTransactionFinalizationProposal: { _ in
                    throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                        "Shared component validation failed"
                    )
                },
                buildCovertSignatureMessages: { _ in [Self.signatureMessage] },
                buildMyProofsList: { _ in Self.myProofsList },
                buildBlames: { _ in Self.blames }
            )
        )
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")
        let skipSharedComponents = OpalFusion.ProtocolModel.ShareCovertComponents(
            serializedComponents: Self.sharedComponents.serializedComponents,
            skipSignatures: true,
            sessionHash: Self.sharedComponents.sessionHash
        )

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
        _ = engine.apply(input: .clockAdvanced, now: Self.instant(1_035))

        let sharedEffects = engine.apply(
            input: .primaryMessage(.shareCovertComponents(skipSharedComponents)),
            now: Self.instant(1_040)
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
                        summary: "Shared component validation failed",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects duplicate skipped-signature results after blame begins")
    func validateSkipSignatureResultCannotOverwriteBlame() {
        var engine = Self.makeEngine()
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")
        let skipSharedComponents = OpalFusion.ProtocolModel.ShareCovertComponents(
            serializedComponents: Self.sharedComponents.serializedComponents,
            skipSignatures: true,
            sessionHash: Self.sharedComponents.sessionHash
        )

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
        _ = engine.apply(input: .clockAdvanced, now: Self.instant(1_035))
        _ = engine.apply(
            input: .primaryMessage(.shareCovertComponents(skipSharedComponents)),
            now: Self.instant(1_040)
        )
        _ = engine.apply(
            input: .primaryMessage(.fusionResult(Self.failureResult)),
            now: Self.instant(1_041)
        )
        #expect(engine.clientState.round?.phase == .blame)
        #expect(engine.clientState.round?.completionStatus == nil)

        let lateResultEffects = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_042)
        )

        #expect(engine.clientState.round?.completionStatus == .protocolIncompatible)
        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(
            lateResultEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "FusionResult arrived out of order",
                        isTerminal: true
                    )
                )
            ]
        )
    }

    @Test("Round engine rejects successful FusionResult after signatures were skipped")
    func validateSkippedSignaturesCannotCompleteSuccessfully() {
        var engine = Self.makeEngine()
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "aabb")
        let skipSharedComponents = OpalFusion.ProtocolModel.ShareCovertComponents(
            serializedComponents: Self.sharedComponents.serializedComponents,
            skipSignatures: true,
            sessionHash: Self.sharedComponents.sessionHash
        )

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
        _ = engine.apply(input: .clockAdvanced, now: Self.instant(1_035))
        _ = engine.apply(
            input: .primaryMessage(.shareCovertComponents(skipSharedComponents)),
            now: Self.instant(1_040)
        )

        let resultEffects = engine.apply(
            input: .primaryMessage(.fusionResult(Self.successResult)),
            now: Self.instant(1_041)
        )

        #expect(engine.clientState.round?.completionStatus == .protocolIncompatible)
        #expect(engine.session.lastError == .protocolIncompatible)
        #expect(
            resultEffects == [
                .emitHostEvent(
                    roundIdentifier: roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "FusionResult reported success after signatures were skipped",
                        isTerminal: true
                    )
                )
            ]
        )
    }
}
