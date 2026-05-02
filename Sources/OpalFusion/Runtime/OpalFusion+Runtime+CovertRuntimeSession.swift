// OpalFusion+Runtime+CovertRuntimeSession.swift

extension OpalFusion.Runtime {
    struct CovertEndpointContext: Sendable, Equatable {
        let roundIdentifier: OpalFusion.Round.Identifier?
        let host: String
        let port: UInt32
        let requiresTLS: Bool?
        let entryPath: String
        let maxPayloadBytes: Int
        let requestTimeoutMilliseconds: UInt64
        let connectTimeout: Duration
        let connectWindow: Duration
        let submitTimeout: Duration
        let submitWindow: Duration
        let spareConnectionCount: Int
    }

    struct CovertPreparationPlan: Sendable, Equatable {
        let endpoint: OpalFusion.Runtime.CovertEndpointContext
        let startedAt: OpalFusion.Execution.Instant
        let deadline: OpalFusion.Execution.Instant
    }

    struct CovertRequest: Sendable, Equatable {
        let endpoint: OpalFusion.Runtime.CovertEndpointContext
        let payload: [UInt8]
        let startedAt: OpalFusion.Execution.Instant
        let deadline: OpalFusion.Execution.Instant
    }

    enum CovertRuntimeSubstate: String, Sendable, Equatable {
        case idle
        case preparing
        case prepared
    }

    struct CovertRuntimeSession: Sendable {
        enum Input: Sendable, Equatable {
            case prepare(endpointContext: OpalFusion.Runtime.CovertEndpointContext)
            case enqueue(message: OpalFusion.ProtocolModel.CovertMessage)
            case covertPrepared
            case covertPreparationFailed(summary: String)
            case covertResponseBytesReceived([UInt8])
            case covertRequestFailed(summary: String)
            case clockAdvanced
            case reset
        }

        enum Effect: Sendable, Equatable {
            case prepareCovertEndpoint(plan: OpalFusion.Runtime.CovertPreparationPlan)
            case performCovertRequest(request: OpalFusion.Runtime.CovertRequest)
            case deliverCovertResponse(OpalFusion.ProtocolModel.CovertResponse)
            case emitProtocolFailure(summary: String)
            case emitTransportFailure(summary: String)
        }

        private struct OutstandingRequest: Sendable, Equatable {
            let request: OpalFusion.Runtime.CovertRequest
            let message: OpalFusion.ProtocolModel.CovertMessage
        }

        private(set) var endpointContext: OpalFusion.Runtime.CovertEndpointContext?
        private(set) var substate: OpalFusion.Runtime.CovertRuntimeSubstate
        private(set) var preparationPlan: OpalFusion.Runtime.CovertPreparationPlan?
        private(set) var queuedMessages: [OpalFusion.ProtocolModel.CovertMessage]
        private(set) var outstandingRequest: OpalFusion.Runtime.CovertRequest?
        private let messageEncoder: OpalFusion.Wire.CovertMessageEncoder
        private let messageDecoder: OpalFusion.Wire.CovertMessageDecoder
        private var outstanding: OutstandingRequest?

        init() {
            self.endpointContext = nil
            self.substate = .idle
            self.preparationPlan = nil
            self.queuedMessages = []
            self.outstandingRequest = nil
            self.messageEncoder = .init()
            self.messageDecoder = .init()
            self.outstanding = nil
        }

        mutating func apply(
            input: OpalFusion.Runtime.CovertRuntimeSession.Input,
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Runtime.CovertRuntimeSession.Effect] {
            switch input {
            case let .prepare(endpointContext):
                return handlePrepare(endpointContext: endpointContext, now: now)
            case let .enqueue(message):
                queuedMessages.append(message)
                return maybeDispatchNextRequest(now: now)
            case .covertPrepared:
                return handleCovertPrepared(now: now)
            case let .covertPreparationFailed(summary):
                reset()
                return [.emitTransportFailure(summary: summary)]
            case let .covertResponseBytesReceived(bytes):
                return handleCovertResponseBytes(bytes, now: now)
            case let .covertRequestFailed(summary):
                reset()
                return [.emitTransportFailure(summary: summary)]
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
            self.outstanding = nil
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
                return [
                    .emitProtocolFailure(
                        summary: "Covert preparation completed before an endpoint was configured"
                    )
                ]
            }

            if now > preparationPlan.deadline {
                reset()
                return [
                    .emitTransportFailure(summary: "Covert endpoint preparation timed out")
                ]
            }

            substate = .prepared
            self.preparationPlan = nil
            return maybeDispatchNextRequest(now: now)
        }

        private mutating func handleCovertResponseBytes(
            _ bytes: [UInt8],
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Runtime.CovertRuntimeSession.Effect] {
            guard let outstanding else {
                reset()
                return [
                    .emitProtocolFailure(
                        summary: "Received a covert response without an outstanding request"
                    )
                ]
            }

            if now > outstanding.request.deadline {
                reset()
                return [
                    .emitTransportFailure(summary: "Covert request timed out")
                ]
            }

            do {
                let response = try messageDecoder.decodeResponse(bytes)
                self.outstanding = nil
                outstandingRequest = nil

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
                        summary: "Covert response decode failed: \(String(describing: error))"
                    )
                ]
            }
        }

        private mutating func handleClockAdvanced(
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Runtime.CovertRuntimeSession.Effect] {
            if let plan = preparationPlan, now > plan.deadline {
                reset()
                return [
                    .emitTransportFailure(summary: "Covert endpoint preparation timed out")
                ]
            }

            if let outstanding, now > outstanding.request.deadline {
                reset()
                return [
                    .emitTransportFailure(summary: "Covert request timed out")
                ]
            }

            return []
        }

        private mutating func maybeDispatchNextRequest(
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Runtime.CovertRuntimeSession.Effect] {
            guard outstanding == nil, substate == .prepared else {
                return []
            }
            guard queuedMessages.isEmpty == false else {
                return []
            }
            guard let endpointContext else {
                return [
                    .emitProtocolFailure(
                        summary: "Covert request was queued before an endpoint was configured"
                    )
                ]
            }

            let message = queuedMessages.removeFirst()

            do {
                let payload = try messageEncoder.encode(message)
                guard payload.count <= endpointContext.maxPayloadBytes else {
                    return [
                        .emitProtocolFailure(
                            summary: "Covert payload exceeded the configured size limit"
                        )
                    ]
                }

                let deadline = now.advanced(by: effectiveSubmitTimeout(for: endpointContext))
                let request = OpalFusion.Runtime.CovertRequest(
                    endpoint: endpointContext,
                    payload: payload,
                    startedAt: now,
                    deadline: deadline
                )
                let outstanding = OutstandingRequest(
                    request: request,
                    message: message
                )

                self.outstanding = outstanding
                self.outstandingRequest = request

                return [.performCovertRequest(request: request)]
            } catch {
                return [
                    .emitProtocolFailure(
                        summary: "Covert request encode failed: \(String(describing: error))"
                    )
                ]
            }
        }

        private mutating func reset() {
            endpointContext = nil
            substate = .idle
            preparationPlan = nil
            queuedMessages = []
            outstanding = nil
            outstandingRequest = nil
        }

        private func effectiveSubmitTimeout(
            for endpointContext: OpalFusion.Runtime.CovertEndpointContext
        ) -> Duration {
            let configuredTimeout = Duration.milliseconds(
                Int64(endpointContext.requestTimeoutMilliseconds)
            )
            return configuredTimeout.wholeMilliseconds <= endpointContext.submitTimeout.wholeMilliseconds
                ? configuredTimeout
                : endpointContext.submitTimeout
        }
    }
}
