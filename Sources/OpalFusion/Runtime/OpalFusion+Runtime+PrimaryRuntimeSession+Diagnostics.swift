// OpalFusion+Runtime+PrimaryRuntimeSession+Diagnostics.swift

import OpalDiagnostics

extension OpalFusion.Runtime.PrimaryRuntimeSession {
    mutating func logPreRoundInboundMessage(
        _ message: OpalFusion.ProtocolModel.ServerMessage,
        payloadBytes: Int
    ) {
        guard shouldTracePreRoundTraffic else {
            return
        }

        preRoundTrace.updateSequence += 1
        preRoundTrace.lastInboundKind = .init(message: message)
        preRoundTrace.lastInboundPayloadBytes = payloadBytes

        switch message {
        case .serverHello:
            recordPrimaryMessageReceived(
                messageKind: "ServerHello",
                payloadBytes: payloadBytes
            )
        case .tierStatusUpdate:
            recordPrimaryMessageReceived(
                messageKind: "TierStatusUpdate",
                payloadBytes: payloadBytes
            )
        case .fusionBegin:
            recordPrimaryMessageReceived(
                messageKind: "FusionBegin",
                payloadBytes: payloadBytes
            )
        case let .serverFailure(failure):
            var fields = [
                OpalDiagnostics.Field.operation("primary_message_receive"),
                OpalDiagnostics.Field.messageKind("ServerFailure"),
                OpalDiagnostics.Field.payloadByteCount(payloadBytes)
            ]
            if let message = failure.message {
                fields.append(OpalDiagnostics.Field.errorMessage(message))
            }
            OpalDiagnostics.logger(category: .fusionPrimary).record(
                event: .primaryMessageReceived,
                level: .opalFusionDefault(for: .primaryMessageReceived),
                fields: fields
            )
        case .startRound, .blindSignatureResponses, .allCommitments, .shareCovertComponents,
                .fusionResult, .theirProofsList, .restartRound:
            break
        }
    }

    mutating func recordAcceptedPreRoundInboundMessage(
        _ message: OpalFusion.ProtocolModel.ServerMessage
    ) {
        guard case .serverHello = message,
              engine.session.connectionSubstate == .awaitingFusionBegin else {
            return
        }

        preRoundTrace.sawServerHello = true
    }

    mutating func logPreRoundOutboundMessage(
        _ message: OpalFusion.ProtocolModel.ClientMessage,
        payloadBytes: Int
    ) {
        switch message {
        case .clientHello:
            preRoundTrace.wroteClientHello = true
            recordPrimaryMessageSent(
                messageKind: "ClientHello",
                payloadBytes: payloadBytes
            )
        case .joinPools:
            preRoundTrace.wroteJoinPools = true
            recordPrimaryMessageSent(
                messageKind: "JoinPools",
                payloadBytes: payloadBytes
            )
        case .playerCommit, .myProofsList, .blames:
            break
        }
    }

    func recordLifecycleEvent(
        phase: String
    ) {
        OpalDiagnostics.logger(category: .fusionPrimary).record(
            event: .handshakePhaseChanged,
            level: .opalFusionDefault(for: .handshakePhaseChanged),
            fields: [
                .operation("handshake"),
                .phase(phase)
            ]
        )
    }

    mutating func recordFailureEvent(
        summary: String,
        errorCode: OpalDiagnostics.ErrorCode = .transportUnavailable
    ) {
        OpalDiagnostics.logger(category: .fusionTransport).record(
            event: .transportError,
            level: .opalFusionDefault(for: .transportError),
            fields: [
                .operation("primary_runtime")
            ] + OpalDiagnostics.Field.sanitizedSummaryFields(
                errorCode: errorCode,
                summary: summary
            )
        )
    }

    mutating func recordFailureEventUnlessRoundIsTerminal(
        summary: String
    ) {
        guard engine.round?.substate != .terminal else {
            return
        }

        recordFailureEvent(summary: summary)
    }

    func recordPrimaryMessageReceived(
        messageKind: String,
        payloadBytes: Int
    ) {
        recordPrimaryMessage(
            OpalDiagnostics.Event.primaryMessageReceived,
            operation: "primary_message_receive",
            messageKind: messageKind,
            payloadBytes: payloadBytes
        )
    }

    func recordPrimaryMessageSent(
        messageKind: String,
        payloadBytes: Int
    ) {
        recordPrimaryMessage(
            OpalDiagnostics.Event.primaryMessageSent,
            operation: "primary_message_send",
            messageKind: messageKind,
            payloadBytes: payloadBytes
        )
    }

    func recordPrimaryMessage(
        _ event: OpalDiagnostics.Event,
        operation: String,
        messageKind: String,
        payloadBytes: Int
    ) {
        OpalDiagnostics.logger(category: .fusionPrimary).record(
            event: event,
            level: .opalFusionDefault(for: event),
            fields: [
                .operation(operation),
                .messageKind(messageKind),
                .payloadByteCount(payloadBytes)
            ]
        )
    }
}
