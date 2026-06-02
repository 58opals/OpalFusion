// OpalFusion+Runtime+LiveRuntimeDriver+ImplementationGroup3.swift

import Foundation
import OpalDiagnostics

extension OpalFusion.Runtime.LiveRuntimeDriver {
    func process(
        _ effect: OpalFusion.Runtime.PrimaryRuntimeSession.Effect
    ) async {
        switch effect {
        case let .writePrimaryBytes(bytes):
            guard let primaryTransport else {
                await handle(
                    .primaryTransportFailed(
                        summary: "Primary transport was unavailable"
                    )
                )
                return
            }
            do {
                try await primaryTransport.write(bytes)
                runtimeSession.recordWrittenPrimaryFrame(bytes)
            } catch {
                OpalDiagnostics.logger(category: .fusionTransport).record(
                    event: .transportError,
                    level: .opalFusionDefault(for: .transportError),
                    traceID: .opalFusionRound(runtimeSession.engine.round?.identifier),
                    fields: [
                        .operation("primary_write"),
                        .frameByteCount(bytes.count)
                    ] + OpalDiagnostics.Field.errorFields(for: error)
                )
                await handle(
                    .diagnosedPrimaryTransportFailed(
                        summary: "Primary write failed"
                    )
                )
            }
        case let .prepareCovertEndpoint(plan):
            guard let covertTransport else {
                return
            }
            covertPreparationTask?.cancel()
            covertPreparationTask = Task { [covertTransport] in
                do {
                    try await covertTransport.prepare(plan)
                    guard Task.isCancelled == false else {
                        return
                    }
                    await self.handleCovertPreparedIfCurrent(plan: plan)
                } catch {
                    guard Task.isCancelled == false else {
                        return
                    }
                    let roundTraceIdentifier = self.roundTraceIdentifierForCovertPreparation(
                        plan: plan
                    )
                    OpalDiagnostics.logger(category: .fusionCovert).record(
                        event: .covertPrepareFailed,
                        level: .opalFusionDefault(for: .covertPrepareFailed),
                        traceID: .opalFusionRound(roundTraceIdentifier),
                        fields: [
                            .operation("covert_prepare")
                        ] + OpalDiagnostics.Field.errorFields(for: error)
                    )
                    await self.handleCovertPreparationFailureIfCurrent(
                        summary: "Covert endpoint preparation failed",
                        plan: plan
                    )
                }
            }
        case let .performCovertRequest(request):
            guard let covertTransport else {
                return
            }
            covertRequestTask?.cancel()
            covertRequestTask = Task { [covertTransport] in
                do {
                    let responseBytes = try await covertTransport.perform(request)
                    guard Task.isCancelled == false else {
                        return
                    }
                    await self.handleCovertResponseIfCurrent(
                        responseBytes,
                        request: request
                    )
                } catch {
                    guard Task.isCancelled == false else {
                        return
                    }
                    OpalDiagnostics.logger(category: .fusionCovert).record(
                        event: .covertRequestFailed,
                        level: .opalFusionDefault(for: .covertRequestFailed),
                        traceID: .opalFusionRound(request.roundIdentifier),
                        fields: [
                            .operation("covert_request"),
                            .payloadByteCount(
                                request.payload.count
                            )
                        ] + OpalDiagnostics.Field.errorFields(for: error)
                    )
                    await self.handleCovertRequestFailureIfCurrent(
                        summary: "Covert request failed",
                        request: request
                    )
                }
            }
        case .resetCovertTransport:
            cancelCovertTasks()
            if let covertTransport {
                await covertTransport.reset()
            }
        case let .requestParticipantReservation(context):
            let participantReservationSource = self.participantReservationSource
            let roundIdentifier = context.roundIdentifier
            participantReservationTask?.cancel()
            participantReservationTask = Task { [participantReservationSource] in
                do {
                    let reservation = try await participantReservationSource.reserveParticipant(
                        for: context
                    )
                    guard Task.isCancelled == false else {
                        return
                    }
                    await self.handleHostOperationIfCurrent(
                        roundIdentifier: roundIdentifier,
                        staleOperation: "participant reservation",
                        input: .participantReservationLoaded(reservation)
                    )
                } catch {
                    guard Task.isCancelled == false else {
                        return
                    }
                    await self.handleHostOperationIfCurrent(
                        roundIdentifier: roundIdentifier,
                        staleOperation: "participant reservation rejection",
                        input: .participantReservationRejected
                    )
                }
            }
        case let .requestTransactionFinalization(roundIdentifier, proposal):
            let transactionAssembler = self.transactionAssembler
            transactionFinalizationTask?.cancel()
            transactionFinalizationTask = Task { [transactionAssembler] in
                do {
                    let transaction = try await transactionAssembler.finalizeTransaction(
                        for: roundIdentifier,
                        proposal: proposal
                    )
                    guard Task.isCancelled == false else {
                        return
                    }
                    await self.handleHostOperationIfCurrent(
                        roundIdentifier: roundIdentifier,
                        staleOperation: "transaction finalization",
                        input: .finalizedTransactionLoaded(transaction)
                    )
                } catch let failure as OpalFusion.Host.TransactionFinalizationFailure {
                    guard Task.isCancelled == false else {
                        return
                    }
                    await self.handleHostOperationIfCurrent(
                        roundIdentifier: roundIdentifier,
                        staleOperation: "transaction finalization rejection",
                        input: .transactionFinalizationRejected(failure)
                    )
                } catch {
                    guard Task.isCancelled == false else {
                        return
                    }
                    await self.handleHostOperationIfCurrent(
                        roundIdentifier: roundIdentifier,
                        staleOperation: "transaction finalization rejection",
                        input: .transactionFinalizationRejected(
                            .transactionAssemblyFailed(
                                summary: "Host transaction finalization failed"
                            )
                        )
                    )
                }
            }
        case let .emitHostEvent(roundIdentifier, event):
            await hostEventSink(roundIdentifier, event)

            if let roundIdentifier {
                await eventObserver?.receive(event, for: roundIdentifier)
            }
        }
    }
}
