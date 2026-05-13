// OpalFusion+Runtime+CovertRuntimeSession.swift

extension OpalFusion.Runtime {
    struct CovertRuntimeSession: Sendable {
        private(set) var endpointContext: OpalFusion.Runtime.CovertEndpointContext?
        private(set) var substate: OpalFusion.Runtime.CovertRuntimeSubstate
        private(set) var preparationPlan: OpalFusion.Runtime.CovertPreparationPlan?
        private(set) var queuedMessages: [OpalFusion.ProtocolModel.CovertMessage]
        private(set) var outstandingRequest: OpalFusion.Runtime.CovertRequest?
        private let messageEncoder: OpalFusion.Wire.CovertMessageEncoder
        private let messageDecoder: OpalFusion.Wire.CovertMessageDecoder

        init() {
            self.endpointContext = nil
            self.substate = .idle
            self.preparationPlan = nil
            self.queuedMessages = []
            self.outstandingRequest = nil
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
            case let .enqueue(message):
                guard endpointContext != nil else {
                    return protocolFailure(
                        summary: "Covert request was queued before an endpoint was configured"
                    )
                }
                queuedMessages.append(message)
                return maybeDispatchNextRequest(now: now)
            case .covertPrepared:
                return handleCovertPrepared(now: now)
            case let .covertPreparationFailed(summary):
                return transportFailure(summary: summary)
            case let .covertResponseBytesReceived(bytes):
                return handleCovertResponseBytes(bytes, now: now)
            case let .covertRequestFailed(summary):
                return transportFailure(summary: summary)
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
            self.endpointContext = endpointContext
            self.substate = .preparing
            self.queuedMessages = []
            self.outstandingRequest = nil

            let plan = OpalFusion.Runtime.CovertPreparationPlan(
                endpoint: endpointContext,
                startedAt: now,
                deadline: now.advanced(by: endpointContext.connectWindow)
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
                return transportFailure(summary: "Covert endpoint preparation timed out")
            }

            substate = .prepared
            self.preparationPlan = nil
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

                if case .serverFailure = response {
                    reset()
                    return [.deliverCovertResponse(response)]
                }

                var effects: [OpalFusion.Runtime.CovertRuntimeSession.Effect] = [
                    .deliverCovertResponse(response)
                ]
                effects.append(contentsOf: maybeDispatchNextRequest(now: now))
                return effects
            } catch {
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
                return transportFailure(summary: "Covert endpoint preparation timed out")
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

                let deadline = now.advanced(by: effectiveSubmitTimeout(for: endpointContext))
                let request = OpalFusion.Runtime.CovertRequest(
                    endpoint: endpointContext,
                    payload: payload,
                    startedAt: now,
                    deadline: deadline
                )

                self.outstandingRequest = request

                return [.performCovertRequest(request: request)]
            } catch {
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
        }

        private func effectiveSubmitTimeout(
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
                endpointContext.submitTimeout,
                endpointContext.submitWindow
            )
        }
    }
}
