// OpalFusion+Mosaic+OpalMainnetAlpha+CandidateAdmissionDocument~Signing.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha.CandidateAdmissionDocument {
    static func deriveSignatureDigest(
        discoveryEpochStartUnixSeconds: UInt64,
        candidateSetDigest: [UInt8],
        discoveryIdentity: OpalCrypto.Signature.BIP340.VerificationKey,
        controlIdentity: OpalFusion.Mosaic.Attempt.ControlIdentity,
        expiryUnixSeconds: UInt64
    ) throws(ValidationError) -> [UInt8] {
        guard candidateSetDigest.count == 32 else {
            throw .invalidCandidateSetDigestByteCount(
                actual: candidateSetDigest.count
            )
        }
        let deadlines: OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestDeadlineSchedule
        do {
            deadlines = try OpalFusion.Mosaic.OpalMainnetAlpha
                .PrivateDeploymentPolicy.frozen.preManifestDeadlines(
                    forEpochStartingAt: discoveryEpochStartUnixSeconds
                )
        } catch {
            throw .invalidDiscoveryEpoch
        }
        guard expiryUnixSeconds == deadlines.controlRosterAgreement else {
            throw .invalidExpiry
        }
        let controlVerificationKey = try Self.controlVerificationKey(
            for: controlIdentity
        )
        guard discoveryIdentity.rawRepresentation
                != controlVerificationKey.rawRepresentation else {
            throw .identicalDiscoveryAndControlIdentity
        }
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        do {
            try encoder.writeText(
                OpalFusion.Mosaic.OpalMainnetAlpha
                    .PrivateDeploymentNostrSelector.identifier
            )
            try encoder.writeText(
                OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue
            )
            try encoder.writeFixedBytes(
                OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash,
                byteCount: 32
            )
            encoder.writeUInt64(discoveryEpochStartUnixSeconds)
            try encoder.writeFixedBytes(candidateSetDigest, byteCount: 32)
            try encoder.writeFixedBytes(
                [UInt8](discoveryIdentity.rawRepresentation),
                byteCount: 32
            )
            try encoder.writeFixedBytes(
                controlIdentity.validatedBytes,
                byteCount: 32
            )
            encoder.writeUInt64(expiryUnixSeconds)
        } catch {
            preconditionFailure("Validated candidate admission fields must encode.")
        }
        return OpalFusion.Mosaic.OpalMainnetAlpha.RoleSeedValidator.hash(
            domainSuffix: "private-deployment/candidate-admission",
            fields: [
                OpalFusion.Mosaic.OpalMainnetAlpha
                    .PrivateDeploymentNostrSelector.identifierBytes,
                encoder.encodedBytes,
            ]
        )
    }

    static func controlVerificationKey(
        for controlIdentity: OpalFusion.Mosaic.Attempt.ControlIdentity
    ) throws(ValidationError) -> OpalCrypto.Signature.BIP340.VerificationKey {
        do {
            return try .init(
                rawRepresentation: Data(controlIdentity.validatedBytes)
            )
        } catch {
            throw .invalidControlIdentity
        }
    }
}
