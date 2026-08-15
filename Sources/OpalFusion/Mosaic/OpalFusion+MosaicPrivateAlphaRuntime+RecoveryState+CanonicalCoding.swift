// OpalFusion+MosaicPrivateAlphaRuntime+RecoveryState+CanonicalCoding.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime.RecoveryState {
    private static var magic: [UInt8] { [0x4F, 0x46, 0x4D, 0x52] }
    private static var version: UInt16 { 4 }

    static func decode(
        from canonicalBytes: Data,
        expectedBinding: OpalFusion.MosaicPrivateAlphaRuntime.Binding
    ) throws -> Self {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard canonicalBytes.count <= maximumSnapshotByteCount else {
            throw Runtime.Failure.opaqueByteCountLimitExceeded
        }
        let state: Self
        do {
            state = try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: Array(canonicalBytes)
            ) { decoder in
                guard try decoder.readFixedBytes(byteCount: magic.count)
                        == magic else {
                    throw Runtime.Failure.malformedRecoverySnapshot
                }
                let decodedVersion = try decoder.readUInt16()
                guard decodedVersion == version else {
                    throw Runtime.Failure.unsupportedRecoveryVersion(
                        decodedVersion
                    )
                }
                let binding = try Runtime.Binding(
                    attemptIdentifier: Data(
                        try decoder.readFixedBytes(byteCount: 32)
                    ),
                    generationIdentifier: Data(
                        try decoder.readFixedBytes(byteCount: 32)
                    ),
                    materialIdentifier: Data(
                        try decoder.readFixedBytes(byteCount: 32)
                    )
                )
                guard let phase = Runtime.Phase(
                    recoveryTag: try decoder.readUInt8()
                ) else {
                    throw Runtime.Failure.malformedRecoverySnapshot
                }
                return Self(
                    binding: binding,
                    revision: try decoder.readUInt64(),
                    discoveryEpochStartUnixSeconds:
                        try decoder.readUInt64(),
                    phase: phase,
                    preManifestDocuments: try decoder.readVector(
                        maximumCount: maximumRecordCount
                    ) { decoder in
                        Data(try decoder.readBytes(
                            maximumByteCount: maximumRecordByteCount
                        ))
                    },
                    preManifestAbortCause:
                        try decodePreManifestAbortCause(from: &decoder),
                    manifestState: try decodeManifestState(from: &decoder),
                    postManifestJournalState:
                        try decodePostManifestJournalState(from: &decoder),
                    publicationState:
                        try decodePublicationState(from: &decoder),
                    terminalState: try decodeTerminalState(from: &decoder)
                )
            }
        } catch let failure as Runtime.Failure {
            throw failure
        } catch let failure as OpalFusion.Mosaic.CanonicalCodingError {
            switch failure {
            case .truncatedInput:
                throw Runtime.Failure.partialRecoverySnapshot
            case .trailingBytes:
                throw Runtime.Failure.nonCanonicalRecoverySnapshot
            default:
                throw Runtime.Failure.malformedRecoverySnapshot
            }
        } catch {
            throw Runtime.Failure.malformedRecoverySnapshot
        }
        guard state.binding == expectedBinding else {
            throw Runtime.Failure.recoveryBindingMismatch
        }
        try state.validate()
        guard try state.canonicalBytes() == canonicalBytes else {
            throw Runtime.Failure.nonCanonicalRecoverySnapshot
        }
        return state
    }

    func encode() throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeFixedBytes(Self.magic, byteCount: Self.magic.count)
        encoder.writeUInt16(Self.version)
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
        encoder.writeUInt64(revision)
        encoder.writeUInt64(discoveryEpochStartUnixSeconds)
        try encoder.writeVector(preManifestDocuments) { encoder, bytes in
            try encoder.writeBytes(Array(bytes))
        }
        try Self.encodePreManifestAbortCause(
            preManifestAbortCause,
            to: &encoder
        )
        try Self.encodeManifestState(manifestState, to: &encoder)
        encoder.writeUInt8(postManifestJournalState.rawValue)
        try Self.encodePublicationState(publicationState, to: &encoder)
        try Self.encodeTerminalState(terminalState, to: &encoder)
        return encoder.encodedBytes
    }

    func validate() throws {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        do {
            _ = try OpalFusion.Mosaic.OpalMainnetAlpha.PrivateDeploymentPolicy
                .frozen.preManifestDeadlines(
                    forEpochStartingAt: discoveryEpochStartUnixSeconds
                )
        } catch {
            throw Runtime.Failure.invalidDiscoveryEpoch
        }
        guard preManifestDocuments.count <= Self.maximumRecordCount else {
            throw Runtime.Failure.opaqueByteCountLimitExceeded
        }
        try validateOpaqueRecords(preManifestDocuments)
        switch manifestState {
        case .forming:
            guard phase.isPreManifest,
                  postManifestJournalState == .uninitialized else {
                throw Runtime.Failure.partialRecoverySnapshot
            }
            _ = try Runtime.restorePrivateDeploymentFormation(
                discoveryEpochStartUnixSeconds:
                    discoveryEpochStartUnixSeconds,
                phase: phase,
                canonicalDocuments: preManifestDocuments
            )
            try validatePreManifestAbortCause()
            if case let .authorized(reason, evidence) = terminalState {
                guard reason == .aborted,
                      publicationState == .none else {
                    throw Runtime.Failure.contradictoryRecoverySnapshot
                }
                _ = try validatePreManifestTerminalEvidence(evidence)
            }
        case let .validated(proposal, manifest):
            guard preManifestAbortCause == .none else {
                throw Runtime.Failure.contradictoryRecoverySnapshot
            }
            try validateOpaque(proposal)
            try validateOpaque(manifest)
            guard !phase.isPreManifest
            else {
                throw Runtime.Failure.contradictoryRecoverySnapshot
            }
            let proof = try Runtime.restorePrivateDeploymentProof(
                discoveryEpochStartUnixSeconds:
                    discoveryEpochStartUnixSeconds,
                canonicalDocuments: preManifestDocuments
            )
            guard Data(proof.proposalValidation.canonicalBody) == proposal,
                  Data(proof.completeManifest.canonicalBytes) == manifest else {
                throw Runtime.Failure.contradictoryRecoverySnapshot
            }
            switch publicationState {
            case .none:
                break
            case .formation:
                throw Runtime.Failure.contradictoryRecoverySnapshot
            case let .terminal(reason, event, _, evidence):
                _ = try validatePostManifestTerminalEvidence(
                    evidence,
                    expectedReason: reason,
                    expectedEvent: event
                )
            }
            if case let .authorized(reason, evidence) = terminalState {
                _ = try validatePostManifestTerminalEvidence(
                    evidence,
                    expectedReason: reason
                )
            }
        }
        if case let .authorized(_, evidence) = terminalState {
            guard publicationState == .none else {
                throw Runtime.Failure.contradictoryRecoverySnapshot
            }
            try validateOpaque(evidence)
        }
        try validatePublicationState()
    }

    static func transitionIdentifier(
        binding: OpalFusion.MosaicPrivateAlphaRuntime.Binding,
        expectedSnapshot: Data?,
        replacementSnapshot: Data
    ) throws -> Data {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeText("OpalFusion/MosaicPrivateAlpha/transition/2")
        try encoder.writeFixedBytes(
            Array(binding.attemptIdentifier), byteCount: 32
        )
        try encoder.writeFixedBytes(
            Array(binding.generationIdentifier), byteCount: 32
        )
        try encoder.writeFixedBytes(
            Array(binding.materialIdentifier), byteCount: 32
        )
        try encoder.writeOptional(expectedSnapshot) { encoder, snapshot in
            try encoder.writeFixedBytes(
                Array(sha256(snapshot)), byteCount: 32
            )
        }
        try encoder.writeFixedBytes(
            Array(sha256(replacementSnapshot)), byteCount: 32
        )
        return sha256(Data(encoder.encodedBytes))
    }

    private static func encodeManifestState(
        _ state: OpalFusion.MosaicPrivateAlphaRuntime.ManifestRecoveryState,
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        switch state {
        case .forming:
            encoder.writeUInt8(0)
        case let .validated(proposal, manifest):
            encoder.writeUInt8(1)
            try encoder.writeBytes(Array(proposal))
            try encoder.writeBytes(Array(manifest))
        }
    }

    private static func encodePreManifestAbortCause(
        _ cause: OpalFusion.MosaicPrivateAlphaRuntime
            .PreManifestAbortCauseRecoveryState,
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        switch cause {
        case .none:
            encoder.writeUInt8(0)
        case let .equivocation(event):
            encoder.writeUInt8(1)
            try encoder.writeBytes(Array(try event.canonicalRecoveryBytes()))
        case let .invalidAuthenticatedMessage(event):
            encoder.writeUInt8(2)
            try encoder.writeBytes(Array(try event.canonicalRecoveryBytes()))
        }
    }

    private static func decodePreManifestAbortCause(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime
        .PreManifestAbortCauseRecoveryState {
        switch try decoder.readUInt8() {
        case 0:
            return .none
        case 1:
            return try .equivocation(
                .decodeRecoveryBytes(Data(decoder.readBytes(
                    maximumByteCount: maximumRecordByteCount
                )))
            )
        case 2:
            return try .invalidAuthenticatedMessage(
                .decodeRecoveryBytes(Data(decoder.readBytes(
                    maximumByteCount: maximumRecordByteCount
                )))
            )
        default:
            throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                .malformedRecoverySnapshot
        }
    }

    private static func decodeManifestState(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.ManifestRecoveryState {
        switch try decoder.readUInt8() {
        case 0:
            return .forming
        case 1:
            return try .validated(
                privateManifestProposalBytes: Data(decoder.readBytes(
                    maximumByteCount: maximumOpaqueByteCount
                )),
                completeManifestBytes: Data(decoder.readBytes(
                    maximumByteCount: maximumOpaqueByteCount
                ))
            )
        default:
            throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                .malformedRecoverySnapshot
        }
    }

    private static func decodePostManifestJournalState(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime
        .PostManifestJournalRecoveryState {
        guard let state = OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestJournalRecoveryState(
                rawValue: try decoder.readUInt8()
            ) else {
            throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                .malformedRecoverySnapshot
        }
        return state
    }

    private static func encodeTerminalState(
        _ state: OpalFusion.MosaicPrivateAlphaRuntime.TerminalRecoveryState,
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        switch state {
        case .active:
            encoder.writeUInt8(0)
        case let .authorized(reason, evidence):
            encoder.writeUInt8(1)
            encoder.writeUInt8(reason.recoveryTag)
            try encoder.writeBytes(Array(evidence))
        }
    }

    private static func encodePublicationState(
        _ state: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentPublicationRecoveryState,
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        switch state {
        case .none:
            encoder.writeUInt8(0)
        case let .formation(event, endpoints):
            encoder.writeUInt8(1)
            try encoder.writeBytes(Array(try event.canonicalRecoveryBytes()))
            try encoder.writeVector(endpoints) { encoder, endpoint in
                try encoder.writeText(endpoint)
            }
        case let .terminal(reason, event, endpoints, evidence):
            encoder.writeUInt8(2)
            encoder.writeUInt8(reason.recoveryTag)
            try encoder.writeBytes(Array(try event.canonicalRecoveryBytes()))
            try encoder.writeVector(endpoints) { encoder, endpoint in
                try encoder.writeText(endpoint)
            }
            try encoder.writeBytes(Array(evidence))
        }
    }

    private static func decodePublicationState(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime
        .PrivateDeploymentPublicationRecoveryState {
        switch try decoder.readUInt8() {
        case 0:
            return .none
        case 1:
            return try .formation(
                event: .decodeRecoveryBytes(Data(decoder.readBytes(
                    maximumByteCount: maximumRecordByteCount
                ))),
                relayEndpointIdentifiers: decoder.readVector(
                    maximumCount: maximumRelayEndpointCount
                ) { decoder in
                    try decoder.readText(
                        maximumByteCount: maximumRelayEndpointByteCount
                    )
                }
            )
        case 2:
            guard let reason = OpalFusion.MosaicPrivateAlphaRuntime
                .TerminalReason(recoveryTag: try decoder.readUInt8()) else {
                throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                    .malformedRecoverySnapshot
            }
            return try .terminal(
                reason: reason,
                event: .decodeRecoveryBytes(Data(decoder.readBytes(
                    maximumByteCount: maximumRecordByteCount
                ))),
                relayEndpointIdentifiers: decoder.readVector(
                    maximumCount: maximumRelayEndpointCount
                ) { decoder in
                    try decoder.readText(
                        maximumByteCount: maximumRelayEndpointByteCount
                    )
                },
                exactEvidenceBytes: Data(decoder.readBytes(
                    maximumByteCount: maximumOpaqueByteCount
                ))
            )
        default:
            throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                .malformedRecoverySnapshot
        }
    }

    private static func decodeTerminalState(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.TerminalRecoveryState {
        switch try decoder.readUInt8() {
        case 0:
            return .active
        case 1:
            guard let reason = OpalFusion.MosaicPrivateAlphaRuntime
                .TerminalReason(recoveryTag: try decoder.readUInt8()) else {
                throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                    .malformedRecoverySnapshot
            }
            return .authorized(
                reason,
                exactEvidenceBytes: Data(try decoder.readBytes(
                    maximumByteCount: maximumOpaqueByteCount
                ))
            )
        default:
            throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                .malformedRecoverySnapshot
        }
    }

    private func validateOpaqueRecords(_ records: [Data]) throws {
        for record in records {
            guard !record.isEmpty else {
                throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                    .emptyExactBytes
            }
            guard record.count <= Self.maximumRecordByteCount else {
                throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                    .opaqueByteCountLimitExceeded
            }
        }
    }

    private func validatePublicationState() throws {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard publicationState != .none else { return }
        guard terminalState == .active,
              preManifestDocuments.count >= 2 else {
            throw Runtime.Failure.contradictoryRecoverySnapshot
        }
        let relaySet = try OpalFusion.Mosaic.OpalMainnetAlpha
            .RelaySetDocument.decode(
                from: Array(preManifestDocuments[1])
            )
        let expectedEndpoints = relaySet.registrations.map {
            $0.endpoint.normalizedURL
        }
        switch publicationState {
        case .none:
            break
        case let .formation(event, endpoints):
            guard endpoints == expectedEndpoints,
                  preManifestDocuments.contains(
                    try event.canonicalRecoveryBytes()
                  ) else {
                throw Runtime.Failure.contradictoryRecoverySnapshot
            }
            _ = try event.decodeCanonicalNostrEvent()
        case let .terminal(reason, event, endpoints, evidence):
            guard endpoints == expectedEndpoints else {
                throw Runtime.Failure.contradictoryRecoverySnapshot
            }
            _ = try event.decodeCanonicalNostrEvent()
            try validateOpaque(evidence)
            if case .forming = manifestState {
                guard reason == .aborted else {
                    throw Runtime.Failure.contradictoryRecoverySnapshot
                }
                _ = try validatePreManifestTerminalEvidence(
                    evidence,
                    expectedEvent: event
                )
            }
        }
    }

    private func validateOpaque(_ bytes: Data) throws {
        guard !bytes.isEmpty else {
            throw OpalFusion.MosaicPrivateAlphaRuntime.Failure.emptyExactBytes
        }
        guard bytes.count <= Self.maximumOpaqueByteCount else {
            throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                .opaqueByteCountLimitExceeded
        }
    }
}
#endif
