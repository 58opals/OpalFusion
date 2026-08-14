// OpalFusion+Mosaic+OpalMainnetAlpha+PrivateDeploymentAbortDocument.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Canonical terminal abort notice scoped to one discovery epoch and reducer phase.
    struct PrivateDeploymentAbortDocument: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidSelector
            case invalidProtocolIdentifier
            case invalidNetworkGenesisHash
            case invalidDiscoveryEpoch
            case contextKindMismatch
            case phaseMismatch
            case contextMismatch
            case unknownPhase(UInt8)
            case unknownReason(UInt8)
        }

        let discoveryEpochStartUnixSeconds: UInt64
        let phase: OpalFusion.Mosaic.Attempt.Phase
        let context: PrivateDeploymentAbortContext
        let reason: OpalFusion.Mosaic.Attempt.AbortReason

        var canonicalBytes: [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                try encoder.writeText(
                    OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue
                )
                try encoder.writeFixedBytes(
                    OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash,
                    byteCount: 32
                )
                encoder.writeUInt64(discoveryEpochStartUnixSeconds)
                encoder.writeUInt8(UInt8(phase.rawValue))
                try encoder.writeBytes(context.canonicalBytes)
                encoder.writeUInt8(Self.canonicalValue(for: reason))
                return encoder.encodedBytes
            } catch {
                preconditionFailure("A validated private-deployment abort must encode.")
            }
        }

        init(
            discoveryEpochStartUnixSeconds: UInt64,
            phase: OpalFusion.Mosaic.Attempt.Phase,
            context: PrivateDeploymentAbortContext,
            reason: OpalFusion.Mosaic.Attempt.AbortReason
        ) throws(ValidationError) {
            do {
                try PrivateDeploymentPolicy.frozen.validate(
                    epochStart: discoveryEpochStartUnixSeconds
                )
            } catch {
                throw .invalidDiscoveryEpoch
            }
            let expectedContextKind: PrivateDeploymentAbortContext.Kind
            switch phase {
            case .discovery:
                expectedContextKind = .discovery
            case .candidateSetAgreement, .controlRosterAgreement:
                expectedContextKind = .candidateSet
            case .roleSelection:
                expectedContextKind = .controlRoster
            case .manifestAgreement, .walletReservation, .groupedCommitment,
                 .anonymousComponentSubmission, .transcriptAgreement, .bchSigning:
                expectedContextKind = .manifest
            }
            guard context.kind == expectedContextKind else {
                throw .contextKindMismatch
            }
            self.discoveryEpochStartUnixSeconds = discoveryEpochStartUnixSeconds
            self.phase = phase
            self.context = context
            self.reason = reason
        }

        static func decode(
            from encodedBytes: [UInt8],
            expectedPhase: OpalFusion.Mosaic.Attempt.Phase,
            expectedContext: PrivateDeploymentAbortContext
        ) throws -> Self {
            try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: encodedBytes
            ) { decoder in
                guard try decoder.readText()
                        == PrivateDeploymentNostrSelector.identifier else {
                    throw ValidationError.invalidSelector
                }
                guard try decoder.readText()
                        == OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue else {
                    throw ValidationError.invalidProtocolIdentifier
                }
                guard try decoder.readFixedBytes(byteCount: 32)
                        == OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash else {
                    throw ValidationError.invalidNetworkGenesisHash
                }
                let epochStart = try decoder.readUInt64()
                let rawPhase = try decoder.readUInt8()
                guard let phase = OpalFusion.Mosaic.Attempt.Phase(
                    rawValue: Int(rawPhase)
                ) else {
                    throw ValidationError.unknownPhase(rawPhase)
                }
                guard phase == expectedPhase else {
                    throw ValidationError.phaseMismatch
                }
                let context = try PrivateDeploymentAbortContext.decode(
                    from: decoder.readBytes()
                )
                guard context == expectedContext else {
                    throw ValidationError.contextMismatch
                }
                return try .init(
                    discoveryEpochStartUnixSeconds: epochStart,
                    phase: phase,
                    context: context,
                    reason: try reason(for: decoder.readUInt8())
                )
            }
        }

        private static func canonicalValue(
            for reason: OpalFusion.Mosaic.Attempt.AbortReason
        ) -> UInt8 {
            switch reason {
            case .timeout: 0
            case .equivocation: 1
            case .invalidAuthenticatedMessage: 2
            case .missingRequiredParticipant: 3
            }
        }

        private static func reason(
            for canonicalValue: UInt8
        ) throws(ValidationError) -> OpalFusion.Mosaic.Attempt.AbortReason {
            switch canonicalValue {
            case 0: .timeout
            case 1: .equivocation
            case 2: .invalidAuthenticatedMessage
            case 3: .missingRequiredParticipant
            default: throw .unknownReason(canonicalValue)
            }
        }
    }
}
