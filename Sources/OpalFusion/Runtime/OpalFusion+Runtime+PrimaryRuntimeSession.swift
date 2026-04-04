// OpalFusion+Runtime+PrimaryRuntimeSession.swift

extension OpalFusion.Runtime {
    struct PrimaryRuntimeSession: Sendable {
        enum Input: Sendable, Equatable {
            case connected
            case disconnected
            case receivedPrimaryBytes([UInt8])
            case hostInputsLoaded([OpalFusion.Host.ParticipantInput])
            case hostInputsRejected
            case finalizedTransactionLoaded(OpalFusion.Host.FinalizedTransaction)
            case transactionFinalizationRejected
            case clockAdvanced
        }

        enum Effect: Sendable, Equatable {
            case writePrimaryBytes([UInt8])
            case requestHostInputs(roundIdentifier: OpalFusion.Round.Identifier)
            case requestTransactionFinalization(
                roundIdentifier: OpalFusion.Round.Identifier,
                proposal: OpalFusion.Host.TransactionFinalizationProposal
            )
            case emitHostEvent(
                roundIdentifier: OpalFusion.Round.Identifier?,
                event: OpalFusion.Host.Event
            )
            case deferCovertMessage(OpalFusion.ProtocolModel.CovertMessage)
        }

        private(set) var frameDecoder: OpalFusion.Wire.PrimaryFrameDecoder
        private let frameEncoder: OpalFusion.Wire.PrimaryFrameEncoder
        private let messageEncoder: OpalFusion.Wire.PrimaryMessageEncoder
        private let messageDecoder: OpalFusion.Wire.PrimaryMessageDecoder
        private(set) var engine: OpalFusion.Execution.RoundEngine
        private(set) var deferredCovertMessages: [OpalFusion.ProtocolModel.CovertMessage]

        init(
            configuration: OpalFusion.Client.Configuration,
            genesisHash: [UInt8]? = nil,
            joinPools: OpalFusion.ProtocolModel.JoinPools,
            workflow: OpalFusion.Execution.WorkflowContext,
            baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443
        ) {
            self.frameDecoder = .init(configuration: baseline.framing)
            self.frameEncoder = .init(configuration: baseline.framing)
            self.messageEncoder = .init()
            self.messageDecoder = .init()
            self.engine = .init(
                configuration: configuration,
                genesisHash: genesisHash,
                joinPools: joinPools,
                workflow: workflow,
                baseline: baseline
            )
            self.deferredCovertMessages = []
        }

        var clientState: OpalFusion.Client.State {
            engine.clientState
        }

        var lastError: OpalFusion.Client.Error? {
            engine.session.lastError
        }

        mutating func apply(
            input: OpalFusion.Runtime.PrimaryRuntimeSession.Input,
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] {
            switch input {
            case .connected:
                return translate(
                    engine.apply(input: .primaryConnected, now: now),
                    now: now
                )
            case .disconnected:
                return translate(
                    engine.apply(input: .primaryDisconnected, now: now),
                    now: now
                )
            case let .receivedPrimaryBytes(bytes):
                return handleReceivedPrimaryBytes(bytes, now: now)
            case let .hostInputsLoaded(inputs):
                return translate(
                    engine.apply(input: .hostInputsLoaded(inputs), now: now),
                    now: now
                )
            case .hostInputsRejected:
                return translate(
                    engine.apply(input: .hostInputsRejected, now: now),
                    now: now
                )
            case let .finalizedTransactionLoaded(transaction):
                return translate(
                    engine.apply(input: .finalizedTransactionLoaded(transaction), now: now),
                    now: now
                )
            case .transactionFinalizationRejected:
                return translate(
                    engine.apply(input: .transactionFinalizationRejected, now: now),
                    now: now
                )
            case .clockAdvanced:
                return translate(
                    engine.apply(input: .clockAdvanced, now: now),
                    now: now
                )
            }
        }

        private mutating func handleReceivedPrimaryBytes(
            _ bytes: [UInt8],
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] {
            do {
                let payloads = try frameDecoder.append(bytes)
                var runtimeEffects: [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] = []

                for payload in payloads {
                    let message = try messageDecoder.decodeServer(payload)
                    runtimeEffects.append(
                        contentsOf: translate(
                            engine.apply(input: .primaryMessage(message), now: now),
                            now: now
                        )
                    )
                }

                return runtimeEffects
            } catch {
                return protocolFailureEffects(
                    summary: "Primary wire decode failed: \(String(describing: error))",
                    now: now
                )
            }
        }

        private mutating func translate(
            _ engineEffects: [OpalFusion.Execution.RoundEngine.Effect],
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] {
            var runtimeEffects: [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] = []

            for effect in engineEffects {
                switch effect {
                case let .sendPrimary(message):
                    do {
                        let payload = try messageEncoder.encode(message)
                        let framed = try frameEncoder.encode(payload: payload)
                        runtimeEffects.append(.writePrimaryBytes(framed))
                    } catch {
                        return runtimeEffects + protocolFailureEffects(
                            summary: "Primary wire encode failed: \(String(describing: error))",
                            now: now
                        )
                    }
                case let .submitCovert(message):
                    deferredCovertMessages.append(message)
                    runtimeEffects.append(.deferCovertMessage(message))
                case let .requestHostInputs(roundIdentifier):
                    runtimeEffects.append(.requestHostInputs(roundIdentifier: roundIdentifier))
                case let .requestTransactionFinalization(roundIdentifier, proposal):
                    runtimeEffects.append(
                        .requestTransactionFinalization(
                            roundIdentifier: roundIdentifier,
                            proposal: proposal
                        )
                    )
                case let .emitHostEvent(roundIdentifier, event):
                    runtimeEffects.append(
                        .emitHostEvent(
                            roundIdentifier: roundIdentifier,
                            event: event
                        )
                    )
                }
            }

            return runtimeEffects
        }

        private mutating func protocolFailureEffects(
            summary: String,
            now: OpalFusion.Execution.Instant
        ) -> [OpalFusion.Runtime.PrimaryRuntimeSession.Effect] {
            translate(
                engine.apply(
                    input: .protocolRejected(summary: summary),
                    now: now
                ),
                now: now
            )
        }
    }
}
