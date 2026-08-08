// OpalFusion+Mosaic+OpalMainnetAlpha+CanonicalWireCodec~Manifest.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha.CanonicalWireCodec {
    static func encodeManifestCore(
        _ core: OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifestCore
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try writeManifestCore(core, to: &encoder)
        return encoder.encodedBytes
    }

    static func decodeManifestCore(
        from encodedBytes: [UInt8],
        expectedContext: OpalFusion.Mosaic.OpalMainnetAlpha.ManifestProposalContext
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifestCore {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try readManifestCore(
                from: &decoder,
                expectedContext: expectedContext
            )
        }
    }

    static func encodeManifest(
        _ manifest: OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifest
    ) -> [UInt8] {
        manifest.canonicalBytes
    }

    static func encodeManifest(
        core: OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifestCore,
        signatures: [OpalFusion.Mosaic.Attempt.ManifestSignature]
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try writeManifestCore(core, to: &encoder)
        try encoder.writeVector(signatures) { encoder, signature in
            try encoder.writeFixedBytes(
                signature.signer.validatedBytes,
                byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
            )
            try encoder.writeFixedBytes(
                signature.rawRepresentation,
                byteCount: 64
            )
        }
        return encoder.encodedBytes
    }

    static func decodeManifest(
        from encodedBytes: [UInt8],
        expectedContext: OpalFusion.Mosaic.OpalMainnetAlpha.ManifestProposalContext
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifest {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            let core = try readManifestCore(
                from: &decoder,
                expectedContext: expectedContext
            )
            let signatures = try decoder.readVector { decoder in
                OpalFusion.Mosaic.Attempt.ManifestSignature(
                    signer: .init(
                        validatedBytes: try decoder.readFixedBytes(
                            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
                        )
                    ),
                    rawRepresentation: try decoder.readFixedBytes(byteCount: 64)
                )
            }
            for index in signatures.indices.dropFirst() {
                let previous = signatures[index - 1].signer.validatedBytes
                let current = signatures[index].signer.validatedBytes
                guard previous.lexicographicallyPrecedes(current) else {
                    if previous == current {
                        throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                            .duplicateManifestSigner
                    }
                    throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                        .nonCanonicalManifestSignatureOrder
                }
            }
            return try .init(core: core, signatures: signatures)
        }
    }

    private static func writeManifestCore(
        _ core: OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifestCore,
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        try encoder.writeText(core.protocolIdentifier)
        try encoder.writeFixedBytes(
            core.networkGenesisHash,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        try encoder.writeFixedBytes(
            core.candidateSetDigest,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        try encoder.writeFixedBytes(
            core.controlRosterDigest,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        try encoder.writeFixedBytes(
            core.roleSeed,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        try encoder.writeVector(core.sortedRosterMembers) { encoder, member in
            try encoder.writeFixedBytes(
                member.controlIdentity.validatedBytes,
                byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
            )
            encoder.writeUInt8(member.role.mainnetAlphaCanonicalValue)
        }
        try encoder.writeFixedBytes(
            core.roster.conductor.validatedBytes,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        try encoder.writeVector(core.orderedContributors) { encoder, contributor in
            try encoder.writeFixedBytes(
                contributor.validatedBytes,
                byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
            )
        }
        try encoder.writeFixedBytes(
            core.opaquePoolIdentifier,
            byteCount: OpalFusion.Mosaic.OpalMainnetAlpha
                .opaquePoolIdentifierByteCount
        )
        encoder.writeUInt8(core.componentCount)
        encoder.writeUInt64(core.feeRateSatoshisPerByte)
        encoder.writeUInt64(core.minimumExcessFeeSatoshis)
        encoder.writeUInt64(core.maximumExcessFeeSatoshis)
        try encoder.writeBytes(
            [UInt8](core.blindSigningVerificationKey.subjectPublicKeyInfo)
        )
        try encoder.writeFixedBytes(
            core.contributorNonceAllocationDigest,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        try encoder.writeText(core.transportProfileIdentifier)
        try encoder.writeFixedBytes(
            core.relaySetDigest,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        encoder.writeUInt64(core.deadlines.phaseStart)
        encoder.writeUInt64(core.deadlines.walletReservation)
        encoder.writeUInt64(core.deadlines.groupedCommitment)
        encoder.writeUInt64(core.deadlines.anonymousComponentSubmission)
        encoder.writeUInt64(core.deadlines.transcriptAgreement)
        encoder.writeUInt64(core.deadlines.bchSigning)
        try encoder.writeText(core.transactionProfileIdentifier)
    }

    private static func readManifestCore(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder,
        expectedContext: OpalFusion.Mosaic.OpalMainnetAlpha.ManifestProposalContext
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifestCore {
        let expectedProfile = OpalFusion.Mosaic.Profile.opalMainnetAlpha
        guard try decoder.readText() == expectedProfile.rawValue else {
            throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError.profileMismatch
        }
        guard try decoder.readFixedBytes(byteCount: 32)
            == OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash else {
            throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError.networkMismatch
        }
        let candidateSetDigest = try decoder.readFixedBytes(byteCount: 32)
        let controlRosterDigest = try decoder.readFixedBytes(byteCount: 32)
        let roleSeed = try decoder.readFixedBytes(byteCount: 32)
        let rosterMembers = try decoder.readVector { decoder in
            let identity = OpalFusion.Mosaic.Attempt.ControlIdentity(
                validatedBytes: try decoder.readFixedBytes(byteCount: 32)
            )
            let role = try OpalFusion.Mosaic.Role(
                mainnetAlphaCanonicalValue: decoder.readUInt8()
            )
            return OpalFusion.Mosaic.Attempt.RosterMember(
                controlIdentity: identity,
                role: role
            )
        }
        for index in rosterMembers.indices.dropFirst() {
            let previous = rosterMembers[index - 1].controlIdentity.validatedBytes
            let current = rosterMembers[index].controlIdentity.validatedBytes
            guard previous.lexicographicallyPrecedes(current) else {
                if previous == current {
                    throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                        .duplicateControlIdentity
                }
                throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                    .nonCanonicalRosterOrder
            }
        }
        let conductor = OpalFusion.Mosaic.Attempt.ControlIdentity(
            validatedBytes: try decoder.readFixedBytes(byteCount: 32)
        )
        let contributors = try decoder.readVector { decoder in
            OpalFusion.Mosaic.Attempt.ControlIdentity(
                validatedBytes: try decoder.readFixedBytes(byteCount: 32)
            )
        }
        let opaquePoolIdentifier = try decoder.readFixedBytes(
            byteCount: OpalFusion.Mosaic.OpalMainnetAlpha
                .opaquePoolIdentifierByteCount
        )
        let componentCount = Int(try decoder.readUInt8())
        let feeRate = try decoder.readUInt64()
        let minimumExcess = try decoder.readUInt64()
        let maximumExcess = try decoder.readUInt64()
        let blindSigningVerificationKey: OpalCrypto.RSABSSA.VerificationKey
        do {
            blindSigningVerificationKey = try .init(
                subjectPublicKeyInfo: Data(try decoder.readBytes())
            )
        } catch {
            throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                .invalidBlindSigningKey
        }
        let nonceAllocationDigest = try decoder.readFixedBytes(byteCount: 32)
        guard try decoder.readText() == expectedProfile.transportProfile.rawValue else {
            throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                .transportProfileMismatch
        }
        let relaySetDigest = try decoder.readFixedBytes(byteCount: 32)
        let deadlines = try OpalFusion.Mosaic.OpalMainnetAlpha.DeadlineSchedule(
            phaseStart: decoder.readUInt64(),
            walletReservation: decoder.readUInt64(),
            groupedCommitment: decoder.readUInt64(),
            anonymousComponentSubmission: decoder.readUInt64(),
            transcriptAgreement: decoder.readUInt64(),
            bchSigning: decoder.readUInt64()
        )
        guard try decoder.readText()
            == expectedProfile.transactionProfileIdentifier else {
            throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                .transactionProfileMismatch
        }

        let expectedRoleElection = expectedContext.roleElection
        guard controlRosterDigest == expectedRoleElection.controlRosterDigest,
              roleSeed == expectedRoleElection.roleSeed,
              rosterMembers == expectedRoleElection.roster.members.sorted(by: {
                  $0.controlIdentity.validatedBytes.lexicographicallyPrecedes(
                      $1.controlIdentity.validatedBytes
                  )
              }),
              conductor == expectedRoleElection.roster.conductor,
              contributors == expectedRoleElection.roster.contributors.sorted(by: {
                  $0.validatedBytes.lexicographicallyPrecedes($1.validatedBytes)
              }) else {
            throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError.rosterMismatch
        }
        guard componentCount
            == OpalFusion.Mosaic.OpalMainnetAlpha.componentCountPerContributor else {
            throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                .invalidComponentCount(actual: componentCount)
        }
        guard feeRate == OpalFusion.Mosaic.OpalMainnetAlpha.feeRateSatoshisPerByte,
              minimumExcess
                == OpalFusion.Mosaic.OpalMainnetAlpha.minimumExcessFeeSatoshis,
              maximumExcess
                == OpalFusion.Mosaic.OpalMainnetAlpha.maximumExcessFeeSatoshis else {
            throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError.invalidFeeTerms
        }

        let core = try OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifestCore(
            candidateSetDigest: candidateSetDigest,
            roleElection: expectedRoleElection,
            opaquePoolIdentifier: opaquePoolIdentifier,
            blindSigningVerificationKey: blindSigningVerificationKey,
            contributorNonceAllocationDigest: nonceAllocationDigest,
            relaySetDigest: relaySetDigest,
            deadlines: deadlines
        )
        try core.validateProposal(against: expectedContext)
        return core
    }
}
