// OpalFusion+Runtime+LiveRuntimeDriver+ImplementationGroup4.swift

import Foundation
import OpalDiagnostics

extension OpalFusion.Runtime.LiveRuntimeDriver {
    func tearDownTransports() async {
        guard isRunning else {
            return
        }

        isRunning = false
        cancelCovertTasks()
        cancelHostTasks()
        primaryReadTask?.cancel()
        primaryReadTask = nil
        clockTask?.cancel()
        clockTask = nil
        if let primaryTransport {
            await primaryTransport.close()
            self.primaryTransport = nil
        }
        if let covertTransport {
            await covertTransport.reset()
            self.covertTransport = nil
        }
    }

    func canReconnectAfter(
        _ input: OpalFusion.Runtime.PrimaryRuntimeSession.Input
    ) -> Bool {
        guard runtimeSession.engine.round == nil else {
            return false
        }

        return switch input {
        case .disconnected, .primaryTransportFailed, .diagnosedPrimaryTransportFailed:
            true
        default:
            false
        }
    }

    func cancelCovertTasks() {
        covertPreparationTask?.cancel()
        covertPreparationTask = nil
        covertRequestTask?.cancel()
        covertRequestTask = nil
    }

    func roundTraceIdentifierForCovertPreparation(
        plan: OpalFusion.Runtime.CovertPreparationPlan
    ) -> OpalFusion.Round.Identifier? {
        guard runtimeSession.covertSession.preparationPlan == plan else {
            return plan.endpoint.roundIdentifier
        }

        return runtimeSession.engine.round?.identifier ?? plan.endpoint.roundIdentifier
    }

    func cancelHostTasks() {
        participantReservationTask?.cancel()
        participantReservationTask = nil
        transactionFinalizationTask?.cancel()
        transactionFinalizationTask = nil
    }

    func handleCovertPreparedIfCurrent(
        plan: OpalFusion.Runtime.CovertPreparationPlan
    ) async {
        guard runtimeSession.covertSession.preparationPlan == plan else {
            return
        }

        await handle(.covertPrepared)
    }

    func handleCovertPreparationFailureIfCurrent(
        summary: String,
        plan: OpalFusion.Runtime.CovertPreparationPlan
    ) async {
        guard runtimeSession.covertSession.preparationPlan == plan else {
            return
        }

        await handle(.covertPreparationFailed(summary: summary))
    }

    func handleCovertResponseIfCurrent(
        _ responseBytes: [UInt8],
        request: OpalFusion.Runtime.CovertRequest
    ) async {
        guard runtimeSession.covertSession.outstandingRequest == request else {
            return
        }

        await handle(.receivedCovertResponseBytes(responseBytes))
    }

    func handleCovertRequestFailureIfCurrent(
        summary: String,
        request: OpalFusion.Runtime.CovertRequest
    ) async {
        guard runtimeSession.covertSession.outstandingRequest == request else {
            return
        }

        await handle(.covertRequestFailed(summary: summary))
    }

    func handleHostOperationIfCurrent(
        roundIdentifier: OpalFusion.Round.Identifier,
        staleOperation: String,
        input: OpalFusion.Runtime.PrimaryRuntimeSession.Input
    ) async {
        guard runtimeSession.engine.round?.identifier == roundIdentifier else {
            OpalDiagnostics.logger(category: .fusionRound).record(
                event: .roundProgressed,
                level: .opalFusionDefault(for: .roundProgressed),
                traceID: .opalFusionRound(roundIdentifier),
                fields: [
                    .operation("stale_host_operation"),
                    .phase(staleOperation)
                ]
            )
            return
        }

        await handle(input)
    }

    func emitSnapshotIfNeeded() async {
        let snapshot = currentSnapshot
        guard snapshot != lastEmittedSnapshot else {
            return
        }

        lastEmittedSnapshot = snapshot
        await snapshotSink(snapshot)
    }

    func logPreRoundDisconnectIfNeeded() {
        let trace = runtimeSession.preRoundTrace
        guard runtimeSession.engine.round == nil,
              trace.wroteClientHello || trace.wroteJoinPools || trace.lastInboundKind != nil else {
            return
        }

        var fields: [OpalDiagnostics.Field] = [
            .operation("primary_preround_disconnect"),
            .messageKind(trace.lastInboundKind),
            .phase(preRoundHandshakePhase)
        ]
        if let payloadByteCount = trace.lastInboundPayloadBytes {
            fields.append(
                .payloadByteCount(payloadByteCount)
            )
        }
        OpalDiagnostics.logger(category: .fusionPrimary).record(
            event: .primaryConnectionPeerEOF,
            level: .opalFusionDefault(for: .primaryConnectionPeerEOF),
            fields: fields
        )
    }
}
