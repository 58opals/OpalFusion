// OpalFusion+MosaicPrivateAlphaRuntime+RecoveryState+PreManifestTerminal.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime.RecoveryState {
    static func makePreManifestTerminalEvidence(
        binding: OpalFusion.MosaicPrivateAlphaRuntime.Binding,
        phase: OpalFusion.MosaicPrivateAlphaRuntime.Phase,
        event: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent,
        wasLocallyPublished: Bool,
        predecessorRevision: UInt64,
        priorSnapshotDigest: Data
    ) throws -> Data {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeText(
            "OpalFusion/MosaicPrivateAlpha/pre-manifest-terminal/2"
        )
        try encoder.writeFixedBytes(
            Array(binding.attemptIdentifier), byteCount: 32
        )
        try encoder.writeFixedBytes(
            Array(binding.generationIdentifier), byteCount: 32
        )
        try encoder.writeFixedBytes(
            Array(binding.materialIdentifier), byteCount: 32
        )
        encoder.writeUInt8(phase.recoveryTag)
        encoder.writeUInt8(wasLocallyPublished ? 0 : 1)
        encoder.writeUInt64(predecessorRevision)
        try encoder.writeBytes(Array(try event.canonicalRecoveryBytes()))
        try encoder.writeFixedBytes(
            Array(priorSnapshotDigest), byteCount: 32
        )
        return Data(encoder.encodedBytes)
    }

    func validatePreManifestTerminalEvidence(
        _ evidence: Data,
        expectedEvent: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent? = nil
    ) throws -> OpalFusion.Mosaic.Attempt.AbortReason {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        let decoded = try OpalFusion.Mosaic.CanonicalDecoder.decode(
            from: Array(evidence)
        ) { decoder in
            guard try decoder.readText(maximumByteCount: 80)
                    == "OpalFusion/MosaicPrivateAlpha/pre-manifest-terminal/2"
            else {
                throw Runtime.Failure.malformedRecoverySnapshot
            }
            let binding = try Runtime.Binding(
                attemptIdentifier: Data(
                    decoder.readFixedBytes(byteCount: 32)
                ),
                generationIdentifier: Data(
                    decoder.readFixedBytes(byteCount: 32)
                ),
                materialIdentifier: Data(
                    decoder.readFixedBytes(byteCount: 32)
                )
            )
            guard let phase = Runtime.Phase(
                recoveryTag: try decoder.readUInt8()
            ) else {
                throw Runtime.Failure.malformedRecoverySnapshot
            }
            let origin = try decoder.readUInt8()
            guard origin <= 1 else {
                throw Runtime.Failure.malformedRecoverySnapshot
            }
            let predecessorRevision = try decoder.readUInt64()
            let event = try Runtime.PrivateDeploymentEvent
                .decodeRecoveryBytes(Data(decoder.readBytes(
                    maximumByteCount: Self.maximumRecordByteCount
                )))
            let priorDigest = Data(
                try decoder.readFixedBytes(byteCount: 32)
            )
            return (
                binding,
                phase,
                origin == 0,
                predecessorRevision,
                event,
                priorDigest
            )
        }
        guard decoded.0 == binding,
              decoded.1 == phase,
              expectedEvent == nil || expectedEvent == decoded.4,
              try Self.makePreManifestTerminalEvidence(
                binding: decoded.0,
                phase: decoded.1,
                event: decoded.4,
                wasLocallyPublished: decoded.2,
                predecessorRevision: decoded.3,
                priorSnapshotDigest: decoded.5
              ) == evidence else {
            throw Runtime.Failure.contradictoryRecoverySnapshot
        }
        let revisionDelta: UInt64
        if decoded.2 {
            switch (publicationState, terminalState) {
            case let (.terminal(reason, event, _, storedEvidence), .active):
                guard reason == .aborted,
                      event == decoded.4,
                      storedEvidence == evidence else {
                    throw Runtime.Failure.contradictoryRecoverySnapshot
                }
                revisionDelta = 1
            case let (.none, .authorized(reason, storedEvidence)):
                guard reason == .aborted,
                      storedEvidence == evidence else {
                    throw Runtime.Failure.contradictoryRecoverySnapshot
                }
                revisionDelta = 2
            default:
                throw Runtime.Failure.contradictoryRecoverySnapshot
            }
        } else {
            guard case let .authorized(reason, storedEvidence) = terminalState,
                  reason == .aborted,
                  storedEvidence == evidence,
                  publicationState == .none else {
                throw Runtime.Failure.contradictoryRecoverySnapshot
            }
            revisionDelta = 1
        }
        let expectedRevision = decoded.3.addingReportingOverflow(
            revisionDelta
        )
        guard !expectedRevision.overflow,
              revision == expectedRevision.partialValue else {
            throw Runtime.Failure.contradictoryRecoverySnapshot
        }
        var predecessor = self
        predecessor.revision = decoded.3
        predecessor.publicationState = .none
        predecessor.terminalState = .active
        try predecessor.validate()
        guard try predecessor.digest() == decoded.5 else {
            throw Runtime.Failure.contradictoryRecoverySnapshot
        }
        let formation = try Runtime.restorePrivateDeploymentFormation(
            discoveryEpochStartUnixSeconds:
                discoveryEpochStartUnixSeconds,
            phase: phase,
            canonicalDocuments: preManifestDocuments
        )
        let nostrEvent = try decoded.4.decodeCanonicalNostrEvent()
        let authority = try Runtime.privateDeploymentAbortAuthority(
            formation: formation,
            signerIdentity: nostrEvent.publicKey
        )
        let document = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrCodec.decodeAbort(
                nostrEvent,
                authority: authority,
                currentUnixSeconds: decoded.4.acceptedAtUnixSeconds
            )
        if decoded.2 {
            let expectedReason = try predecessor
                .expectedPreManifestDeadlineAbortReason()
            guard document.reason == expectedReason,
                  nostrEvent.template.createdAt
                    == decoded.4.acceptedAtUnixSeconds,
                  nostrEvent.template.createdAt
                    <= authority.expiryUnixSeconds else {
                throw Runtime.Failure.contradictoryRecoverySnapshot
            }
            switch predecessor.preManifestAbortCause {
            case let .equivocation(causeEvent),
                 let .invalidAuthenticatedMessage(causeEvent):
                guard nostrEvent.template.createdAt
                        >= causeEvent.acceptedAtUnixSeconds else {
                    throw Runtime.Failure.contradictoryRecoverySnapshot
                }
            case .none:
                break
            }
            if expectedReason == .missingRequiredParticipant
                || expectedReason == .timeout {
                let phaseBoundary = try Runtime.preManifestTimeoutBoundary(
                    phase: phase,
                    discoveryEpochStartUnixSeconds:
                        discoveryEpochStartUnixSeconds
                )
                guard nostrEvent.template.createdAt >= phaseBoundary else {
                    throw Runtime.Failure.contradictoryRecoverySnapshot
                }
            }
        }
        return document.reason
    }
}
#endif
