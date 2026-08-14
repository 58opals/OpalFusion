// OpalFusion+Mosaic+OpalMainnetAlpha+ContributorNonceAllocationDocument.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Canonical public allocation sources for the exact role-selected contributors.
    ///
    /// Allocation sources are non-secret public domain inputs. They are not salts, private
    /// nonces, signing keys, or a substitute for the production material owner's fresh entropy.
    struct ContributorNonceAllocationDocument: Sendable, Equatable {
        struct ContributorAllocationEntry: Sendable, Equatable {
            let contributor: OpalFusion.Mosaic.Attempt.ControlIdentity
            let publicSource: [UInt8]

            /// Records one caller-generated public source after role selection.
            ///
            /// The caller must generate this value independently of wallet material and prevent
            /// reuse across contributors, attempts, and retries. It must not encode an amount,
            /// outpoint, address, wallet identifier, salt, secret nonce, or signing key.
            init(
                contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
                appGeneratedPublicSource publicSource: [UInt8]
            ) {
                self.contributor = contributor
                self.publicSource = Array(publicSource)
            }
        }

        enum ValidationError: Error, Sendable, Equatable {
            case invalidSelector
            case unsupportedProfile
            case invalidProtocolIdentifier
            case invalidNetworkGenesisHash
            case controlRosterDigestMismatch
            case invalidContributorCount(actual: Int)
            case unknownContributor([UInt8])
            case duplicateContributor([UInt8])
            case missingContributors([[UInt8]])
            case invalidPublicSourceByteCount(contributor: [UInt8], actual: Int)
            case duplicatePublicSource
            case nonCanonicalOrdering
        }

        let controlRosterDigest: [UInt8]
        let allocations: [ContributorAllocationEntry]

        var canonicalBytes: [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                try encoder.writeText(OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue)
                try encoder.writeFixedBytes(
                    OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash,
                    byteCount: 32
                )
                try encoder.writeFixedBytes(controlRosterDigest, byteCount: 32)
                try encoder.writeVector(allocations) { encoder, allocation in
                    try encoder.writeFixedBytes(
                        allocation.contributor.validatedBytes,
                        byteCount: 32
                    )
                    try encoder.writeFixedBytes(allocation.publicSource, byteCount: 32)
                }
                return encoder.encodedBytes
            } catch {
                preconditionFailure("A validated nonce allocation document must encode.")
            }
        }

        var digest: [UInt8] {
            RoleSeedValidator.hash(
                domainSuffix: "private-deployment/contributor-nonce-allocation",
                fields: [
                    PrivateDeploymentNostrSelector.identifierBytes,
                    canonicalBytes,
                ]
            )
        }

        init(
            roleElection: OpalFusion.Mosaic.Attempt.RoleElectionResult,
            allocations: [ContributorAllocationEntry]
        ) throws(ValidationError) {
            guard roleElection.profile == .opalMainnetAlpha else {
                throw .unsupportedProfile
            }
            let expectedContributors = Set(
                roleElection.roster.contributors.map {
                    Data($0.validatedBytes)
                }
            )
            guard (6 ... 8).contains(expectedContributors.count) else {
                throw .invalidContributorCount(actual: expectedContributors.count)
            }
            var allocationsByContributor: [Data: ContributorAllocationEntry] = [:]
            var publicSources: Set<Data> = []
            for allocation in allocations {
                let contributor = Data(allocation.contributor.validatedBytes)
                guard expectedContributors.contains(contributor) else {
                    throw .unknownContributor([UInt8](contributor))
                }
                guard allocationsByContributor[contributor] == nil else {
                    throw .duplicateContributor([UInt8](contributor))
                }
                guard allocation.publicSource.count == 32 else {
                    throw .invalidPublicSourceByteCount(
                        contributor: [UInt8](contributor),
                        actual: allocation.publicSource.count
                    )
                }
                guard publicSources.insert(Data(allocation.publicSource)).inserted else {
                    throw .duplicatePublicSource
                }
                allocationsByContributor[contributor] = .init(
                    contributor: allocation.contributor,
                    appGeneratedPublicSource: allocation.publicSource
                )
            }
            let missingContributors = expectedContributors
                .subtracting(allocationsByContributor.keys)
                .map { [UInt8]($0) }
                .sorted { $0.lexicographicallyPrecedes($1) }
            guard missingContributors.isEmpty else {
                throw .missingContributors(missingContributors)
            }
            self.controlRosterDigest = roleElection.controlRosterDigest
            self.allocations = allocationsByContributor.values.sorted {
                $0.contributor.validatedBytes.lexicographicallyPrecedes(
                    $1.contributor.validatedBytes
                )
            }
        }

        static func decode(
            from encodedBytes: [UInt8],
            roleElection: OpalFusion.Mosaic.Attempt.RoleElectionResult
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
                guard try decoder.readFixedBytes(byteCount: 32)
                        == roleElection.controlRosterDigest else {
                    throw ValidationError.controlRosterDigestMismatch
                }
                let allocations = try decoder.readVector { decoder in
                    ContributorAllocationEntry(
                        contributor: .init(
                            validatedBytes: try decoder.readFixedBytes(byteCount: 32)
                        ),
                        appGeneratedPublicSource:
                            try decoder.readFixedBytes(byteCount: 32)
                    )
                }
                let document = try Self(
                    roleElection: roleElection,
                    allocations: allocations
                )
                guard document.allocations == allocations else {
                    throw ValidationError.nonCanonicalOrdering
                }
                return document
            }
        }
    }
}
