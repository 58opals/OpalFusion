// OpalFusion+Mosaic+OpalMainnetAlpha+AvailabilityBeaconDocument.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Signed availability beacon with exact work-count and throttle validation.
    struct AvailabilityBeaconDocument: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidSelector
            case workBitCountMismatch(expected: UInt16, actual: UInt16)
            case insufficientWork(actual: UInt16)
            case invalidSignature
        }

        let core: AvailabilityBeaconCoreDocument
        let claimedWorkBitCount: UInt16
        let signature: [UInt8]

        var canonicalBodyBytes: [UInt8] {
            Self.canonicalBodyBytes(
                core: core,
                claimedWorkBitCount: claimedWorkBitCount
            )
        }

        var signatureDigest: [UInt8] {
            RoleSeedValidator.hash(
                domainSuffix: "private-deployment/availability-beacon-signature",
                fields: [
                    PrivateDeploymentNostrSelector.identifierBytes,
                    canonicalBodyBytes,
                ]
            )
        }

        var canonicalBytes: [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                try encoder.writeBytes(canonicalBodyBytes)
                try encoder.writeFixedBytes(signature, byteCount: 64)
                return encoder.encodedBytes
            } catch {
                preconditionFailure("A validated availability beacon must encode.")
            }
        }

        init(
            core: AvailabilityBeaconCoreDocument,
            claimedWorkBitCount: UInt16,
            signature: [UInt8]
        ) throws(ValidationError) {
            let actualWorkBitCount = Self.leadingZeroBitCount(in: core.workDigest)
            guard claimedWorkBitCount == actualWorkBitCount else {
                throw .workBitCountMismatch(
                    expected: actualWorkBitCount,
                    actual: claimedWorkBitCount
                )
            }
            guard claimedWorkBitCount
                    >= PrivateDeploymentPolicy.frozen
                        .minimumLeadingZeroWorkBitCount else {
                throw .insufficientWork(actual: claimedWorkBitCount)
            }
            let digest = Self.deriveSignatureDigest(
                core: core,
                claimedWorkBitCount: claimedWorkBitCount
            )
            guard PrivateDeploymentSignatureValidation.verify(
                signatureBytes: signature,
                digestBytes: digest,
                using: core.discoveryIdentity
            ) else {
                throw .invalidSignature
            }
            self.core = core
            self.claimedWorkBitCount = claimedWorkBitCount
            self.signature = Array(signature)
        }

        static func validateWork(
            for core: AvailabilityBeaconCoreDocument
        ) throws(ValidationError) -> UInt16 {
            let workBitCount = leadingZeroBitCount(in: core.workDigest)
            guard workBitCount
                    >= PrivateDeploymentPolicy.frozen
                        .minimumLeadingZeroWorkBitCount else {
                throw .insufficientWork(actual: workBitCount)
            }
            return workBitCount
        }

        static func deriveSignatureDigest(
            core: AvailabilityBeaconCoreDocument,
            claimedWorkBitCount: UInt16
        ) -> [UInt8] {
            RoleSeedValidator.hash(
                domainSuffix: "private-deployment/availability-beacon-signature",
                fields: [
                    PrivateDeploymentNostrSelector.identifierBytes,
                    canonicalBodyBytes(
                        core: core,
                        claimedWorkBitCount: claimedWorkBitCount
                    )
                ]
            )
        }

        static func decode(from encodedBytes: [UInt8]) throws -> Self {
            try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: encodedBytes
            ) { decoder in
                guard try decoder.readText()
                        == PrivateDeploymentNostrSelector.identifier else {
                    throw ValidationError.invalidSelector
                }
                let bodyBytes = try decoder.readBytes()
                let signature = try decoder.readFixedBytes(byteCount: 64)
                return try OpalFusion.Mosaic.CanonicalDecoder.decode(
                    from: bodyBytes
                ) { bodyDecoder in
                    guard try bodyDecoder.readText()
                            == PrivateDeploymentNostrSelector.identifier else {
                        throw ValidationError.invalidSelector
                    }
                    return try .init(
                        core: AvailabilityBeaconCoreDocument.decode(
                            from: bodyDecoder.readBytes()
                        ),
                        claimedWorkBitCount: bodyDecoder.readUInt16(),
                        signature: signature
                    )
                }
            }
        }

        private static func leadingZeroBitCount(in bytes: [UInt8]) -> UInt16 {
            var result: UInt16 = 0
            for byte in bytes {
                guard byte != 0 else {
                    result += 8
                    continue
                }
                result += UInt16(byte.leadingZeroBitCount)
                break
            }
            return result
        }

        private static func canonicalBodyBytes(
            core: AvailabilityBeaconCoreDocument,
            claimedWorkBitCount: UInt16
        ) -> [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                try encoder.writeBytes(core.canonicalBytes)
            } catch {
                preconditionFailure("A validated availability core must encode.")
            }
            encoder.writeUInt16(claimedWorkBitCount)
            return encoder.encodedBytes
        }
    }
}
