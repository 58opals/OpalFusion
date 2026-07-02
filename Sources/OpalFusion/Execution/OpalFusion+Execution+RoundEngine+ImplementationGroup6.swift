// OpalFusion+Execution+RoundEngine+ImplementationGroup6.swift

import Foundation
import OpalDiagnostics

extension OpalFusion.Execution.RoundEngine {
    func hostEventWithoutDiagnostics(
        roundIdentifier: OpalFusion.Round.Identifier?,
        kind: OpalFusion.Host.Event.Kind,
        phase: OpalFusion.Round.Phase,
        summary: String,
        isTerminal: Bool = false
    ) -> OpalFusion.Execution.RoundEngine.Effect {
        return .emitHostEvent(
            roundIdentifier: roundIdentifier,
            event: .init(
                kind: kind,
                phase: phase,
                summary: summary,
                isTerminal: isTerminal
            )
        )
    }

    func recordTransactionProposalFailure(
        _ error: Swift.Error,
        roundIdentifier: OpalFusion.Round.Identifier?
    ) {
        OpalDiagnostics.logger(category: .fusionTransaction).record(
            event: .transactionProposalFailed,
            level: .opalFusionDefault(for: .transactionProposalFailed),
            traceID: .opalFusionRound(roundIdentifier),
            fields: [
                .operation("transaction_proposal"),
                .phase(.assemblingTransaction)
            ] + OpalDiagnostics.Field.errorFields(for: error)
        )
    }

    func recordTransactionSignatureMaterialFailure(
        _ error: Swift.Error,
        roundIdentifier: OpalFusion.Round.Identifier?
    ) {
        OpalDiagnostics.logger(category: .fusionTransaction).record(
            event: .transactionFinalizationFailed,
            level: .opalFusionDefault(for: .transactionFinalizationFailed),
            traceID: .opalFusionRound(roundIdentifier),
            fields: [
                .operation("transaction_signature_material")
            ] + OpalDiagnostics.Field.errorFields(for: error)
        )
    }

    func recordHostEventDiagnostics(
        roundIdentifier: OpalFusion.Round.Identifier?,
        kind: OpalFusion.Host.Event.Kind,
        phase: OpalFusion.Round.Phase,
        summary: String,
        isTerminal: Bool,
        errorCode: OpalDiagnostics.ErrorCode?
    ) {
        let event: OpalDiagnostics.Event
        if kind == .completed {
            event = OpalDiagnostics.Event.roundCompleted
        } else if kind == .failure {
            event = OpalDiagnostics.Event.roundFailed
        } else {
            event = OpalDiagnostics.Event.roundProgressed
        }

        var fields = [
            OpalDiagnostics.Field.operation("host_event"),
            OpalDiagnostics.Field.phase(phase)
        ]
        if isTerminal {
            fields.append(OpalDiagnostics.Field.terminal(true))
        }
        if kind == .failure {
            fields.append(
                contentsOf: OpalDiagnostics.Field.sanitizedSummaryFields(
                    errorCode: errorCode ?? .unknown,
                    summary: summary
                )
            )
        }

        OpalDiagnostics.logger(category: .fusionRound).record(
            event: event,
            level: .opalFusionDefault(for: event),
            traceID: .opalFusionRound(roundIdentifier),
            fields: fields
        )
    }

    func isServerTimeAcceptable(
        _ serverTimeUnixSeconds: UInt64,
        now: OpalFusion.Execution.Instant
    ) -> Bool {
        guard let serverTime = OpalFusion.Execution.Instant(
            validatingUnixSeconds: serverTimeUnixSeconds
        ) else {
            return false
        }
        let maximumDistance = session.baseline.roundTiming.maximumClockDiscrepancy
            .wholeMilliseconds
        guard maximumDistance >= 0 else {
            return false
        }
        let distance = serverTime.distance(to: now).wholeMilliseconds
        return distance >= -maximumDistance && distance <= maximumDistance
    }

    func makeRoundIdentifier(
        from roundPublicKey: [UInt8]
    ) -> OpalFusion.Round.Identifier {
        let hexDigits = Array("0123456789abcdef")
        let hex = roundPublicKey.reduce(into: String()) { partialResult, byte in
            partialResult.append(hexDigits[Int(byte >> 4)])
            partialResult.append(hexDigits[Int(byte & 0x0F)])
        }
        return .init(rawValue: hex)
    }

    func makeParticipantReservationContext(
        roundIdentifier: OpalFusion.Round.Identifier,
        fusionBegin: OpalFusion.ProtocolModel.FusionBegin,
        serverHello: OpalFusion.ProtocolModel.ServerHello
    ) -> OpalFusion.Host.ParticipantReservationContext {
        .init(
            roundIdentifier: roundIdentifier,
            tierSatoshis: fusionBegin.tier,
            numberOfComponents: serverHello.numberOfComponents,
            componentFeeRateSatoshisPerKb: serverHello.componentFeeRateSatoshisPerKb,
            minimumExcessFeeSatoshis: serverHello.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: serverHello.maximumExcessFeeSatoshis
        )
    }

    func makeCovertEndpointContext(
        from fusionBegin: OpalFusion.ProtocolModel.FusionBegin
    ) -> OpalFusion.Runtime.CovertEndpointContext {
        .init(
            roundIdentifier: nil,
            host: fusionBegin.covertDomain,
            port: fusionBegin.covertPort,
            requiresTLS: fusionBegin.covertSsl,
            entryPath: session.configuration.covertChannel.entryPath,
            maxPayloadBytes: session.configuration.covertChannel.maxPayloadBytes,
            requestTimeoutMilliseconds: session.configuration.covertChannel.requestTimeoutMilliseconds,
            connectTimeout: session.baseline.covertTiming.connectTimeout,
            connectWindow: session.baseline.covertTiming.connectWindow,
            submitTimeout: session.baseline.covertTiming.submitTimeout,
            submitWindow: session.baseline.covertTiming.submitWindow,
            spareConnectionCount: session.baseline.covertTiming.spareConnectionCount
        )
    }

    func isValidCovertDomain(
        _ domain: String
    ) -> Bool {
        guard domain.isEmpty == false,
              domain.hasWhitespace == false else {
            return false
        }

        return OpalFusion.Runtime.isValidHostName(domain)
    }

}
