// OpalFusion+Runtime+CovertRuntimeSession.swift

import OpalDiagnostics

extension OpalFusion.Runtime {
    struct CovertRuntimeSession: Sendable {
        private(set) var endpointContext: OpalFusion.Runtime.CovertEndpointContext?
        private(set) var substate: OpalFusion.Runtime.CovertRuntimeSubstate
        private(set) var preparationPlan: OpalFusion.Runtime.CovertPreparationPlan?
        private(set) var queuedMessages: [OpalFusion.ProtocolModel.CovertMessage]
        private(set) var outstandingRequest: OpalFusion.Runtime.CovertRequest?
        private var roundIdentifier: OpalFusion.Round.Identifier?
        private var submitWindowDeadline: OpalFusion.Execution.Instant?
        private let messageEncoder: OpalFusion.Wire.CovertMessageEncoder
        private let messageDecoder: OpalFusion.Wire.CovertMessageDecoder

        init() {
            self.endpointContext = nil
            self.substate = .idle
            self.preparationPlan = nil
            self.queuedMessages = []
            self.outstandingRequest = nil
            self.roundIdentifier = nil
            self.submitWindowDeadline = nil
            self.messageEncoder = .init()
            self.messageDecoder = .init()
        }

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

        private mutating func handlePrepare(
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

        private mutating func handleCovertPrepared(
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

        private mutating func handleCovertResponseBytes(
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

        private mutating func handleClockAdvanced(
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

        private mutating func maybeDispatchNextRequest(
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Runtime.CovertRuntimeSession.Effect] {
            guard outstandingRequest == nil, substate == .prepared else {
                return []
            }
            guard queuedMessages.isEmpty == false else {
                return []
            }
            guard let endpointContext else {
                return protocolFailure(
                    summary: "Covert request was queued before an endpoint was configured"
                )
            }

            let message = queuedMessages.removeFirst()

            do {
                let payload = try messageEncoder.encode(message)
                guard payload.count <= endpointContext.maxPayloadBytes else {
                    return protocolFailure(
                        summary: "Covert payload exceeded the configured size limit"
                    )
                }

                let submitWindowDeadline = submitWindowDeadline
                    ?? now.advanced(by: endpointContext.submitWindow)
                self.submitWindowDeadline = submitWindowDeadline
                guard now <= submitWindowDeadline else {
                    return transportFailure(summary: "Covert request timed out")
                }

                let requestDeadline = now.advanced(by: effectiveRequestTimeout(for: endpointContext))
                let deadline = min(requestDeadline, submitWindowDeadline)
                let request = OpalFusion.Runtime.CovertRequest(
                    endpoint: endpointContext,
                    roundIdentifier: roundIdentifier,
                    payload: payload,
                    startedAt: now,
                    deadline: deadline
                )

                self.outstandingRequest = request
                OpalDiagnostics.logger(category: .fusionCovert).record(
                    event: .covertRequestStarted,
                    level: .opalFusionDefault(for: .covertRequestStarted),
                    traceID: .opalFusionRound(request.roundIdentifier),
                    fields: [
                        .operation("covert_request"),
                        .messageKind(for: message),
                        .payloadByteCount(payload.count)
                    ]
                )

                return [.performCovertRequest(request: request)]
            } catch {
                OpalDiagnostics.logger(category: .fusionCovert).record(
                    event: .covertMessageEncodeFailed,
                    level: .opalFusionDefault(for: .covertMessageEncodeFailed),
                    traceID: .opalFusionRound(endpointContext.roundIdentifier),
                    fields: [
                        .operation("covert_message_encode"),
                        .messageKind(for: message)
                    ] + OpalDiagnostics.Field.errorFields(for: error)
                )
                return protocolFailure(summary: "Covert request encode failed")
            }
        }

        private mutating func protocolFailure(
            summary: String
        ) -> [OpalFusion.Runtime.CovertRuntimeSession.Effect] {
            reset()
            return [.emitProtocolFailure(summary: summary)]
        }

        private mutating func transportFailure(
            summary: String,
            event: OpalDiagnostics.Event = OpalDiagnostics.Event.covertRequestFailed,
            operation: String = "covert_transport"
        ) -> [OpalFusion.Runtime.CovertRuntimeSession.Effect] {
            OpalDiagnostics.logger(category: .fusionCovert).record(
                event: event,
                level: .opalFusionDefault(for: event),
                traceID: .opalFusionRound(
                    outstandingRequest.map(roundTraceIdentifier(for:)) ?? currentRoundTraceIdentifier
                ),
                fields: [
                    .operation(operation)
                ] + OpalDiagnostics.Field.sanitizedSummaryFields(
                    errorCode: .transportUnavailable,
                    summary: summary
                )
            )
            reset()
            return [.emitTransportFailure(summary: summary)]
        }

        private var currentRoundTraceIdentifier: OpalFusion.Round.Identifier? {
            roundIdentifier ?? endpointContext?.roundIdentifier
        }

        private func roundTraceIdentifier(
            for request: OpalFusion.Runtime.CovertRequest
        ) -> OpalFusion.Round.Identifier? {
            request.roundIdentifier ?? currentRoundTraceIdentifier
        }

        private mutating func diagnosedTransportFailure(
            summary: String
        ) -> [OpalFusion.Runtime.CovertRuntimeSession.Effect] {
            reset()
            return [.emitTransportFailure(summary: summary)]
        }

        private mutating func reset() {
            endpointContext = nil
            substate = .idle
            preparationPlan = nil
            queuedMessages = []
            outstandingRequest = nil
            roundIdentifier = nil
            submitWindowDeadline = nil
        }

        private func effectiveRequestTimeout(
            for endpointContext: OpalFusion.Runtime.CovertEndpointContext
        ) -> Duration {
            let requestTimeoutMilliseconds = min(
                endpointContext.requestTimeoutMilliseconds,
                UInt64(Int64.max)
            )
            let configuredTimeout = Duration.milliseconds(
                Int64(requestTimeoutMilliseconds)
            )
            return min(
                configuredTimeout,
                endpointContext.submitTimeout
            )
        }

        private func effectiveConnectTimeout(
            for endpointContext: OpalFusion.Runtime.CovertEndpointContext
        ) -> Duration {
            min(
                endpointContext.connectTimeout,
                endpointContext.connectWindow
            )
        }

        private func recordCovertPrepare(
            _ event: OpalDiagnostics.Event,
            roundIdentifier: OpalFusion.Round.Identifier?
        ) {
            OpalDiagnostics.logger(category: .fusionCovert).record(
                event: event,
                level: .opalFusionDefault(for: event),
                traceID: .opalFusionRound(roundIdentifier),
                fields: [
                    .operation("covert_prepare")
                ]
            )
        }
    }
}
