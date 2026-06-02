// OpalFusion+Runtime+CovertRuntimeSession+ImplementationGroup1.swift

import OpalDiagnostics

extension OpalFusion.Runtime.CovertRuntimeSession {
    mutating func apply(
        input: OpalFusion.Runtime.CovertRuntimeSession.Input,
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Runtime.CovertRuntimeSession.Effect] {
        switch input {
        case let .prepare(endpointContext):
            return handlePrepare(endpointContext: endpointContext, now: now)
        case let .roundIdentifierResolved(roundIdentifier):
            self.roundIdentifier = roundIdentifier
            return []
        case let .enqueue(message):
            guard let endpointContext else {
                return protocolFailure(
                    summary: "Covert request was queued before an endpoint was configured"
                )
            }
            if submitWindowDeadline == nil {
                submitWindowDeadline = now.advanced(by: endpointContext.submitWindow)
            }
            queuedMessages.append(message)
            return maybeDispatchNextRequest(now: now)
        case .covertPrepared:
            return handleCovertPrepared(now: now)
        case let .covertPreparationFailed(summary):
            return diagnosedTransportFailure(summary: summary)
        case let .covertResponseBytesReceived(bytes):
            return handleCovertResponseBytes(bytes, now: now)
        case let .covertRequestFailed(summary):
            return diagnosedTransportFailure(summary: summary)
        case .clockAdvanced:
            return handleClockAdvanced(now: now)
        case .reset:
            reset()
            return []
        }
    }

    mutating func handlePrepare(
        endpointContext: OpalFusion.Runtime.CovertEndpointContext,
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Runtime.CovertRuntimeSession.Effect] {
        recordCovertPrepare(
            OpalDiagnostics.Event.covertPrepareStarted,
            roundIdentifier: endpointContext.roundIdentifier
        )
        self.endpointContext = endpointContext
        self.substate = .preparing
        self.queuedMessages = []
        self.outstandingRequest = nil
        self.roundIdentifier = endpointContext.roundIdentifier
        self.submitWindowDeadline = nil

        let preparationDeadline = now.advanced(
            by: effectiveConnectTimeout(for: endpointContext)
        )
        let plan = OpalFusion.Runtime.CovertPreparationPlan(
            endpoint: endpointContext,
            startedAt: now,
            deadline: preparationDeadline
        )
        self.preparationPlan = plan

        return [.prepareCovertEndpoint(plan: plan)]
    }

    mutating func handleCovertPrepared(
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Runtime.CovertRuntimeSession.Effect] {
        guard endpointContext != nil, let preparationPlan else {
            return protocolFailure(
                summary: "Covert preparation completed before an endpoint was configured"
            )
        }

        if now > preparationPlan.deadline {
            return transportFailure(
                summary: "Covert endpoint preparation timed out",
                event: OpalDiagnostics.Event.covertPrepareFailed,
                operation: "covert_prepare"
            )
        }

        substate = .prepared
        self.preparationPlan = nil
        recordCovertPrepare(
            OpalDiagnostics.Event.covertPrepareSucceeded,
            roundIdentifier: roundIdentifier ?? endpointContext?.roundIdentifier
        )
        return maybeDispatchNextRequest(now: now)
    }

    mutating func handleCovertResponseBytes(
        _ bytes: [UInt8],
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Runtime.CovertRuntimeSession.Effect] {
        guard let outstandingRequest else {
            reset()
            return [
                .emitProtocolFailure(
                    summary: "Received a covert response without an outstanding request"
                )
            ]
        }

        if now > outstandingRequest.deadline {
            return transportFailure(summary: "Covert request timed out")
        }

        do {
            let response = try messageDecoder.decodeResponse(bytes)
            self.outstandingRequest = nil
            OpalDiagnostics.logger(category: .fusionCovert).record(
                event: .covertRequestSucceeded,
                level: .opalFusionDefault(for: .covertRequestSucceeded),
                traceID: .opalFusionRound(roundTraceIdentifier(for: outstandingRequest)),
                fields: [
                    .operation("covert_request"),
                    .payloadByteCount(bytes.count),
                    .messageKind(for: response)
                ]
            )

            if case .serverFailure = response {
                reset()
                return [.deliverCovertResponse(response)]
            }

            let dispatchEffects = maybeDispatchNextRequest(now: now)
            guard dispatchEffects.isEmpty else {
                return dispatchEffects
            }

            submitWindowDeadline = nil
            return [.deliverCovertResponse(response)]
        } catch {
            OpalDiagnostics.logger(category: .fusionCovert).record(
                event: .covertResponseDecodeFailed,
                level: .opalFusionDefault(for: .covertResponseDecodeFailed),
                traceID: .opalFusionRound(roundTraceIdentifier(for: outstandingRequest)),
                fields: [
                    .operation("covert_response_decode"),
                    .payloadByteCount(bytes.count)
                ] + OpalDiagnostics.Field.errorFields(for: error)
            )
            reset()
            return [
                .emitProtocolFailure(
                    summary: "Covert response decode failed"
                )
            ]
        }
    }

    mutating func handleClockAdvanced(
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Runtime.CovertRuntimeSession.Effect] {
        if let plan = preparationPlan, now > plan.deadline {
            return transportFailure(
                summary: "Covert endpoint preparation timed out",
                event: OpalDiagnostics.Event.covertPrepareFailed,
                operation: "covert_prepare"
            )
        }

        if queuedMessages.isEmpty == false,
           let submitWindowDeadline,
           now > submitWindowDeadline {
            return transportFailure(summary: "Covert request timed out")
        }

        if let outstandingRequest, now > outstandingRequest.deadline {
            return transportFailure(summary: "Covert request timed out")
        }

        return []
    }
}
