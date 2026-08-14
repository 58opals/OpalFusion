// OpalFusion+Mosaic+OpalMainnetAlpha+PreManifestDocumentCodec.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Canonical body coding for pre-manifest role and manifest-agreement Nostr payloads.
    enum PreManifestDocumentCodec {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidSelector
            case unknownControlIdentity
            case controlRosterDigestMismatch
            case invalidManifestSigner
            case invalidManifestSignature(
                OpalFusion.Mosaic.Attempt.ManifestSignatureValidation.ValidationError
            )
        }

        static func encodeRoleCommitment(
            _ commitment: OpalFusion.Mosaic.Attempt.RoleCommitment
        ) throws -> [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
            try encoder.writeFixedBytes(
                commitment.candidate.validatedBytes,
                byteCount: 32
            )
            try encoder.writeFixedBytes(
                commitment.controlRosterDigest,
                byteCount: 32
            )
            try encoder.writeFixedBytes(commitment.commitment, byteCount: 32)
            return encoder.encodedBytes
        }

        static func decodeRoleCommitment(
            from encodedBytes: [UInt8],
            controlRoster: OpalFusion.Mosaic.Attempt.ControlRosterBinding
        ) throws -> OpalFusion.Mosaic.Attempt.RoleCommitment {
            try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: encodedBytes
            ) { decoder in
                try requireSelector(from: &decoder)
                let candidate = OpalFusion.Mosaic.Attempt.ControlIdentity(
                    validatedBytes: try decoder.readFixedBytes(byteCount: 32)
                )
                guard controlRoster.controlIdentities.contains(candidate) else {
                    throw ValidationError.unknownControlIdentity
                }
                let controlRosterDigest = try decoder.readFixedBytes(byteCount: 32)
                guard controlRosterDigest == controlRoster.controlRosterDigest else {
                    throw ValidationError.controlRosterDigestMismatch
                }
                return .init(
                    candidate: candidate,
                    controlRosterDigest: controlRosterDigest,
                    commitment: try decoder.readFixedBytes(byteCount: 32)
                )
            }
        }

        static func encodeRoleReveal(
            _ reveal: OpalFusion.Mosaic.Attempt.RoleReveal
        ) throws -> [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
            try encoder.writeFixedBytes(
                reveal.candidate.validatedBytes,
                byteCount: 32
            )
            try encoder.writeFixedBytes(
                reveal.controlRosterDigest,
                byteCount: 32
            )
            try encoder.writeFixedBytes(reveal.randomness, byteCount: 32)
            return encoder.encodedBytes
        }

        static func decodeRoleReveal(
            from encodedBytes: [UInt8],
            controlRoster: OpalFusion.Mosaic.Attempt.ControlRosterBinding
        ) throws -> OpalFusion.Mosaic.Attempt.RoleReveal {
            try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: encodedBytes
            ) { decoder in
                try requireSelector(from: &decoder)
                let candidate = OpalFusion.Mosaic.Attempt.ControlIdentity(
                    validatedBytes: try decoder.readFixedBytes(byteCount: 32)
                )
                guard controlRoster.controlIdentities.contains(candidate) else {
                    throw ValidationError.unknownControlIdentity
                }
                let controlRosterDigest = try decoder.readFixedBytes(byteCount: 32)
                guard controlRosterDigest == controlRoster.controlRosterDigest else {
                    throw ValidationError.controlRosterDigestMismatch
                }
                return .init(
                    candidate: candidate,
                    controlRosterDigest: controlRosterDigest,
                    randomness: try decoder.readFixedBytes(byteCount: 32)
                )
            }
        }

        static func encodeManifestProposal(_ core: RoundManifestCore) throws -> [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
            try encoder.writeBytes(core.canonicalBytes)
            return encoder.encodedBytes
        }

        static func decodeManifestProposal(
            from encodedBytes: [UInt8],
            expectedContext: ManifestProposalContext
        ) throws -> RoundManifestCore {
            try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: encodedBytes
            ) { decoder in
                try requireSelector(from: &decoder)
                return try CanonicalWireCodec.decodeManifestCore(
                    from: decoder.readBytes(),
                    expectedContext: expectedContext
                )
            }
        }

        static func encodeManifestSignature(
            _ signature: OpalFusion.Mosaic.Attempt.ManifestSignature
        ) throws -> [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
            try encoder.writeFixedBytes(
                signature.signer.validatedBytes,
                byteCount: 32
            )
            try encoder.writeFixedBytes(
                signature.rawRepresentation,
                byteCount: 64
            )
            return encoder.encodedBytes
        }

        static func decodeManifestSignature(
            from encodedBytes: [UInt8],
            for binding: OpalFusion.Mosaic.Attempt.ManifestBinding,
            expectedRoster: OpalFusion.Mosaic.Attempt.Roster
        ) throws -> PrivateDeploymentManifestSignatureValidation {
            let signature = try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: encodedBytes
            ) { decoder in
                try requireSelector(from: &decoder)
                return OpalFusion.Mosaic.Attempt.ManifestSignature(
                    signer: .init(
                        validatedBytes: try decoder.readFixedBytes(byteCount: 32)
                    ),
                    rawRepresentation:
                        try decoder.readFixedBytes(byteCount: 64)
                )
            }
            do {
                return try .init(
                    validating: signature,
                    for: binding,
                    expectedRoster: expectedRoster
                )
            } catch let error {
                switch error {
                case .signerNotInRoster:
                    throw ValidationError.invalidManifestSigner
                case let .invalidSignature(validationError):
                    throw ValidationError.invalidManifestSignature(
                        validationError
                    )
                }
            }
        }

        private static func requireSelector(
            from decoder: inout OpalFusion.Mosaic.CanonicalDecoder
        ) throws {
            guard try decoder.readText()
                    == PrivateDeploymentNostrSelector.identifier else {
                throw ValidationError.invalidSelector
            }
        }
    }
}
