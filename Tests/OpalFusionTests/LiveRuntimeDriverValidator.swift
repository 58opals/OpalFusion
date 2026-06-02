// LiveRuntimeDriverValidator.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

struct LiveRuntimeDriverValidator {


































}

extension LiveRuntimeDriverValidator {
    func makeFinalizationFailureDriver(
        primaryTransport: ScriptedPrimaryTransport,
        covertTransport: ScriptedCovertTransport,
        transactionAssembler: BlockingTransactionAssembler,
        eventSink: RecordedHostEventSink,
        nowProvider: ScriptedInstantClock
    ) -> OpalFusion.Runtime.LiveRuntimeDriver {
        OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            workflow: PrimaryRuntimeTestFixtures.workflow,
            participantReservationSource: DelayedParticipantReservationSource(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput],
                participantOutputs: [PrimaryRuntimeTestFixtures.participantOutput]
            ),
            transactionAssembler: transactionAssembler,
            hostEventSink: { roundIdentifier, event in
                await eventSink.record(
                    roundIdentifier: roundIdentifier,
                    event: event
                )
            },
            nowProvider: { await nowProvider.current },
            clockTickInterval: .milliseconds(100),
            primaryTransport: primaryTransport,
            covertTransport: covertTransport
        )
    }

    func driveScriptedRuntimeToPendingTransactionFinalization(
        primaryTransport: ScriptedPrimaryTransport,
        covertTransport: ScriptedCovertTransport,
        nowProvider: ScriptedInstantClock,
        transactionAssembler: BlockingTransactionAssembler
    ) async throws {
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await primaryTransport.recordedWrittenPayloads).isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 996)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverHello(PrimaryRuntimeTestFixtures.serverHello)
            )
        )
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await primaryTransport.recordedWrittenPayloads).count < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_000)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
            )
        )
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await covertTransport.recordedPreparationPlans).isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .startRound(PrimaryRuntimeTestFixtures.startRound)
            )
        )
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await primaryTransport.recordedWrittenPayloads).count < 3 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_032)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .blindSignatureResponses(PrimaryRuntimeTestFixtures.blindSignatureResponses)
            )
        )

        await nowProvider.update(unixSeconds: 1_034)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .allCommitments(PrimaryRuntimeTestFixtures.allCommitments)
            )
        )

        await covertTransport.enqueueResponse(
            try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                PrimaryRuntimeTestFixtures.acknowledgement
            )
        )
        await nowProvider.update(unixSeconds: 1_035)
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await covertTransport.recordedRequests).isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_040)
        await primaryTransport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .shareCovertComponents(PrimaryRuntimeTestFixtures.sharedComponents)
            )
        )
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await transactionAssembler.recordedProposals).isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }
}
