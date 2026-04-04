// ElectronCashInteropValidator.swift

@testable import OpalFusion
import Foundation
import Testing

struct ElectronCashInteropValidator {
    @Test(
        "Real Electron Cash 4.4.3 coordinator smoke reaches terminal success",
        .enabled(
            if: ProcessInfo.processInfo.environment["OPALFUSION_EC_INTEROP"] == "1",
            "Set OPALFUSION_EC_INTEROP=1 and the required OPALFUSION_EC_* variables to run the real Electron Cash interop smoke."
        )
    )
    func validateRealElectronCashCoordinatorInterop() async throws {
        let interopConfiguration = try ElectronCashInteropConfiguration.fromEnvironment()
        let participantInputProvider = DelayedParticipantInputProvider(
            participantInputs: interopConfiguration.participantReservation.inputs,
            participantOutputs: interopConfiguration.participantReservation.outputs
        )
        let transactionAssembler = SigningTransactionAssembler(
            participantInput: interopConfiguration.participantReservation.inputs[0],
            participantInputPrivateKey: interopConfiguration.participantInputPrivateKey
        )
        let eventSink = RecordedHostEventSink()
        let primaryTransport = RecordingPrimaryTransport(
            base: OpalFusion.Runtime.LivePrimaryTransport(
                host: interopConfiguration.clientConfiguration.coordinatorHost,
                port: interopConfiguration.clientConfiguration.coordinatorPort
            )
        )
        let covertTransport = RecordingCovertTransport(
            base: OpalFusion.Runtime.LiveCovertTransport(
                torSocks5: interopConfiguration.clientConfiguration.torSocks5
            )
        )
        let driver = OpalFusion.Runtime.LiveRuntimeDriver(
            configuration: interopConfiguration.clientConfiguration,
            genesisHash: interopConfiguration.genesisHash,
            joinPools: interopConfiguration.joinPools,
            participantInputProvider: participantInputProvider,
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
        defer {
            Task {
                await driver.stop()
            }
        }

        let snapshot = try await withTimeout(.seconds(600)) {
            while true {
                let snapshot = await driver.snapshot()
                if snapshot.clientState.round?.isTerminal == true {
                    return snapshot
                }
                if snapshot.lastError != nil, snapshot.clientState.round == nil {
                    return snapshot
                }
                try await Task.sleep(for: .milliseconds(250))
            }
        }

        #expect(snapshot.lastError == nil)
        #expect(snapshot.clientState.isConnected == true)
        #expect(snapshot.clientState.round?.phase == .completed)
        #expect(snapshot.clientState.round?.completionStatus == .success)

        let clientMessageKinds = await primaryTransport.recordedClientMessages().map(Self.clientKind)
        #expect(
            Self.containsSubsequence(
                clientMessageKinds,
                subsequence: ["clientHello", "joinPools", "playerCommit"]
            )
        )

        let serverMessageKinds = await primaryTransport.recordedServerMessages().map(Self.serverKind)
        #expect(
            Self.containsSubsequence(
                serverMessageKinds,
                subsequence: [
                    "fusionBegin",
                    "startRound",
                    "blindSignatureResponses",
                    "shareCovertComponents",
                    "fusionResult.success",
                ]
            )
        )

        let covertMessageKinds = await covertTransport.recordedRequestMessages().map(Self.covertKind)
        #expect(
            Self.containsSubsequence(
                covertMessageKinds,
                subsequence: ["component", "transactionSignature"]
            )
        )

        #expect(await primaryTransport.recordedOutboundDecodeFailures().isEmpty)
        #expect(await primaryTransport.recordedInboundDecodeFailures().isEmpty)
        #expect(await covertTransport.recordedRequestDecodeFailures().isEmpty)
        #expect(await covertTransport.recordedResponseDecodeFailures().isEmpty)

        let requestedRounds = await participantInputProvider.requestedRounds()
        let finalizedRounds = await transactionAssembler.requestedRounds()
        #expect(requestedRounds.isEmpty == false)
        #expect(finalizedRounds.isEmpty == false)

        let eventSummaries = await eventSink.snapshot().map(\.event.summary)
        #expect(
            Self.containsSubsequence(
                eventSummaries,
                subsequence: [
                    "Primary channel connected; sending ClientHello",
                    "ServerHello received; joining eligible pools",
                    "Fusion warmup started",
                    "StartRound received; collecting reserved inputs and outputs",
                    "Submitting player commitments and blind requests",
                    "Blind signature responses received",
                    "Submitting covert components",
                    "Shared components received; requesting transaction finalization",
                    "Transaction finalized; waiting for signature window",
                    "Submitting covert transaction signatures",
                    "Round completed successfully",
                ]
            )
        )

        let requestRecords = await participantInputProvider.timedRequestRecords()
        let proposalRecords = await transactionAssembler.timedProposalRecords()
        let timedEvents = await eventSink.timedSnapshot()
        #expect(requestRecords.isEmpty == false)
        #expect(proposalRecords.isEmpty == false)
        guard
            let firstReservationRequest = requestRecords.first?.recordedAt,
            let firstProposal = proposalRecords.first?.recordedAt,
            let successEvent = timedEvents.first(where: { $0.event.summary == "Round completed successfully" })?
            .recordedAt
        else {
            Issue.record("Expected timed reservation, proposal, and success-event records")
            return
        }
        #expect(firstReservationRequest <= firstProposal)
        #expect(firstProposal <= successEvent)
    }

    private static func clientKind(
        _ message: OpalFusion.ProtocolModel.ClientMessage
    ) -> String {
        switch message {
        case .clientHello:
            "clientHello"
        case .joinPools:
            "joinPools"
        case .playerCommit:
            "playerCommit"
        case .myProofsList:
            "myProofsList"
        case .blames:
            "blames"
        }
    }

    private static func serverKind(
        _ message: OpalFusion.ProtocolModel.ServerMessage
    ) -> String {
        switch message {
        case .serverHello:
            "serverHello"
        case .tierStatusUpdate:
            "tierStatusUpdate"
        case .fusionBegin:
            "fusionBegin"
        case .startRound:
            "startRound"
        case .blindSignatureResponses:
            "blindSignatureResponses"
        case .allCommitments:
            "allCommitments"
        case .shareCovertComponents:
            "shareCovertComponents"
        case let .fusionResult(result):
            result.isSuccess ? "fusionResult.success" : "fusionResult.failure"
        case .theirProofsList:
            "theirProofsList"
        case .restartRound:
            "restartRound"
        case .serverFailure:
            "serverFailure"
        }
    }

    private static func covertKind(
        _ message: OpalFusion.ProtocolModel.CovertMessage
    ) -> String {
        switch message {
        case .component:
            "component"
        case .transactionSignature:
            "transactionSignature"
        case .ping:
            "ping"
        }
    }

    private static func containsSubsequence<T: Equatable>(
        _ sequence: [T],
        subsequence: [T]
    ) -> Bool {
        guard subsequence.isEmpty == false else {
            return true
        }

        var subsequenceIndex = 0
        for element in sequence where element == subsequence[subsequenceIndex] {
            subsequenceIndex += 1
            if subsequenceIndex == subsequence.count {
                return true
            }
        }

        return false
    }
}
