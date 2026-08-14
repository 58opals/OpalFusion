// MosaicMainnetAlphaPrivateCanonicalContractValidator~Parsing.swift

import Foundation
import Testing
@testable import OpalFusion

extension MosaicMainnetAlphaPrivateCanonicalContractValidator {
    private struct ParserVector {
        let name: String
        let canonicalBytes: [UInt8]
        let decodeCanonicalBytes: ([UInt8]) throws -> [UInt8]
    }

    private struct ProtocolBindingParserVector {
        let name: String
        let canonicalBytes: [UInt8]
        let protocolIdentifierIndex: Int
        let genesisHashIndex: Int
        let decodeCanonicalBytes: ([UInt8]) throws -> [UInt8]
        let matchesProtocolIdentifierError: (any Error) -> Bool
        let matchesGenesisHashError: (any Error) -> Bool
    }

    @Test("Reject malformed canonical documents with deterministic bounds")
    func rejectMalformedCanonicalDocumentsWithDeterministicBounds() async throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let manifest = try MosaicPrivateDeploymentFixtures
            .makeManifestValidation(formation: formation)
        let proposal = try Alpha.PrivateDeploymentManifestProposalValidation(
            manifest: manifest
        )
        let signer = formation.roleElection.roster.controlIdentities[0]
        let signatureBody = try makeSignatureBody(
            signer: signer,
            formation: formation,
            manifest: manifest
        )
        let abortAuthority = try Alpha.PrivateDeploymentAbortAuthority
            .makeRoleSelectionAuthority(
                participant: signer,
                controlRoster: formation.controlRoster
            )
        let abort = try Alpha.PrivateDeploymentAbortDocument(
            discoveryEpochStartUnixSeconds: formation.discovery.epochStart,
            phase: .roleSelection,
            context: abortAuthority.context,
            reason: .timeout
        )
        let roundManifest = try MosaicPrivateDeploymentFixtures
            .makeRoundManifest(
                formation: formation,
                validation: manifest
            )
        let completed = try await MosaicMainnetAlphaBCHCompletionFixtures
            .prepare(manifest: roundManifest)
        let completionValidation = try Alpha
            .PrivateDeploymentCompletionValidation(
                manifest: manifest,
                roundManifest: roundManifest,
                completeTransactionValidation: completed.validation
            )
        let completion = Alpha.PrivateDeploymentCompletionDocument(
            validation: completionValidation
        )
        let payload = try Alpha.PreManifestNostrPayloadDocument
            .makeAvailabilityBeacon(formation.discovery.beacons[0])
        let acknowledgement = formation.acknowledgementSet
            .acknowledgements[0]
        let admission = formation.controlRoster.admissions[0]
        let roleCommitment = try Alpha.PreManifestDocumentCodec
            .encodeRoleCommitment(formation.commitments[0])
        let roleReveal = try Alpha.PreManifestDocumentCodec
            .encodeRoleReveal(formation.reveals[0])
        let vectors: [ParserVector] = [
            .init(name: "opaque pool", canonicalBytes: formation.discovery.pool.canonicalBytes) {
                try Alpha.OpaquePoolDocument.decode(from: $0).canonicalBytes
            },
            .init(name: "relay registration", canonicalBytes: formation.discovery.relaySet.registrations[0].canonicalBytes) {
                try Alpha.RelayRegistrationDocument.decode(from: $0).canonicalBytes
            },
            .init(name: "relay set", canonicalBytes: formation.discovery.relaySet.canonicalBytes) {
                try Alpha.RelaySetDocument.decode(from: $0).canonicalBytes
            },
            .init(name: "beacon core", canonicalBytes: formation.discovery.beacons[0].core.canonicalBytes) {
                try Alpha.AvailabilityBeaconCoreDocument.decode(from: $0).canonicalBytes
            },
            .init(name: "beacon", canonicalBytes: formation.discovery.beacons[0].canonicalBytes) {
                try Alpha.AvailabilityBeaconDocument.decode(from: $0).canonicalBytes
            },
            .init(name: "acknowledgement", canonicalBytes: acknowledgement.canonicalBytes) {
                try Alpha.CandidateSetAcknowledgementDocument.decode(from: $0).canonicalBytes
            },
            .init(name: "acknowledgement set", canonicalBytes: formation.acknowledgementSet.canonicalBytes) {
                try Alpha.CandidateSetAcknowledgementSetDocument.decode(
                    from: $0,
                    candidateSelection: formation.selection
                ).canonicalBytes
            },
            .init(name: "admission", canonicalBytes: admission.canonicalBytes) {
                try Alpha.CandidateAdmissionDocument.decode(from: $0).canonicalBytes
            },
            .init(name: "nonce allocation", canonicalBytes: formation.nonceAllocation.canonicalBytes) {
                try Alpha.ContributorNonceAllocationDocument.decode(
                    from: $0,
                    roleElection: formation.roleElection
                ).canonicalBytes
            },
            .init(name: "role commitment", canonicalBytes: roleCommitment) {
                let decoded = try Alpha.PreManifestDocumentCodec
                    .decodeRoleCommitment(
                        from: $0,
                        controlRoster: formation.controlRoster
                            .controlRosterBinding
                    )
                return try Alpha.PreManifestDocumentCodec
                    .encodeRoleCommitment(decoded)
            },
            .init(name: "role reveal", canonicalBytes: roleReveal) {
                let decoded = try Alpha.PreManifestDocumentCodec.decodeRoleReveal(
                    from: $0,
                    controlRoster: formation.controlRoster.controlRosterBinding
                )
                return try Alpha.PreManifestDocumentCodec.encodeRoleReveal(decoded)
            },
            .init(name: "manifest proposal", canonicalBytes: proposal.canonicalBody) {
                let decoded = try Alpha.PreManifestDocumentCodec
                    .decodeManifestProposal(
                        from: $0,
                        expectedContext: proposal.expectedContext
                    )
                return try Alpha.PreManifestDocumentCodec
                    .encodeManifestProposal(decoded)
            },
            .init(name: "manifest signature", canonicalBytes: signatureBody) {
                _ = try Alpha.PreManifestDocumentCodec.decodeManifestSignature(
                    from: $0,
                    for: proposal.signatureBinding,
                    expectedRoster: manifest.core.roster
                )
                return $0
            },
            .init(name: "abort context", canonicalBytes: abortAuthority.context.canonicalBytes) {
                try Alpha.PrivateDeploymentAbortContext.decode(from: $0)
                    .canonicalBytes
            },
            .init(name: "abort", canonicalBytes: abort.canonicalBytes) {
                try Alpha.PrivateDeploymentAbortDocument.decode(
                    from: $0,
                    expectedPhase: .roleSelection,
                    expectedContext: abortAuthority.context
                ).canonicalBytes
            },
            .init(name: "completion", canonicalBytes: completion.canonicalBytes) {
                try Alpha.PrivateDeploymentCompletionDocument.decode(
                    from: $0,
                    validation: completionValidation
                ).canonicalBytes
            },
            .init(name: "Nostr payload", canonicalBytes: payload.canonicalBytes) {
                try Alpha.PreManifestNostrPayloadDocument.decode(from: $0)
                    .canonicalBytes
            },
        ]

        for vector in vectors {
            #expect(
                try vector.decodeCanonicalBytes(vector.canonicalBytes)
                    == vector.canonicalBytes,
                "Positive parser vector failed: \(vector.name)"
            )
            for count in truncationCounts(for: vector.canonicalBytes.count) {
                #expect(throws: (any Error).self, "Accepted truncated \(vector.name)") {
                    _ = try vector.decodeCanonicalBytes(
                        Array(vector.canonicalBytes.prefix(count))
                    )
                }
            }
            #expect(throws: (any Error).self, "Accepted trailing \(vector.name)") {
                _ = try vector.decodeCanonicalBytes(vector.canonicalBytes + [0])
            }
            var selectorDrift = vector.canonicalBytes
            selectorDrift[4] ^= 1
            #expect(throws: (any Error).self, "Accepted selector drift in \(vector.name)") {
                _ = try vector.decodeCanonicalBytes(selectorDrift)
            }
            for mutationIndex in mutationIndices(for: vector.canonicalBytes.count) {
                var mutation = vector.canonicalBytes
                mutation[mutationIndex] ^= 0x80
                if let recanonicalized = try? vector.decodeCanonicalBytes(mutation) {
                    #expect(
                        recanonicalized == mutation,
                        "Accepted noncanonical byte mutation in \(vector.name)"
                    )
                }
            }
        }

        var unknownContextKind = abortAuthority.context.canonicalBytes
        unknownContextKind[4 + Alpha.PrivateDeploymentNostrSelector.identifier.utf8.count] = 0xFF
        #expect(throws: (any Error).self) {
            _ = try Alpha.PrivateDeploymentAbortContext.decode(
                from: unknownContextKind
            )
        }
        var unknownPayloadKind = payload.canonicalBytes
        let payloadKindIndex = 4
            + Alpha.PrivateDeploymentNostrSelector.identifier.utf8.count
            + 4
            + OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue.utf8.count
            + 32
            + 8
        unknownPayloadKind[payloadKindIndex] = 0xFF
        #expect(
            throws: Alpha.PreManifestNostrPayloadDocument.ValidationError
                .unknownPayloadKind(0xFF)
        ) {
            _ = try Alpha.PreManifestNostrPayloadDocument.decode(
                from: unknownPayloadKind
            )
        }
        var unknownSignerRole = payload.canonicalBytes
        unknownSignerRole[payloadKindIndex + 1] = 0xFF
        #expect(
            throws: Alpha.PreManifestNostrPayloadDocument.ValidationError
                .unknownSignerRole(0xFF)
        ) {
            _ = try Alpha.PreManifestNostrPayloadDocument.decode(
                from: unknownSignerRole
            )
        }

        let abortPhaseIndex = 4
            + Alpha.PrivateDeploymentNostrSelector.identifier.utf8.count
            + 4
            + OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue.utf8.count
            + 32
            + 8
        var unknownAbortPhase = abort.canonicalBytes
        unknownAbortPhase[abortPhaseIndex] = 0xFF
        #expect(
            throws: Alpha.PrivateDeploymentAbortDocument.ValidationError
                .unknownPhase(0xFF)
        ) {
            _ = try Alpha.PrivateDeploymentAbortDocument.decode(
                from: unknownAbortPhase,
                expectedPhase: .roleSelection,
                expectedContext: abortAuthority.context
            )
        }
        var unknownAbortReason = abort.canonicalBytes
        unknownAbortReason[unknownAbortReason.count - 1] = 0xFF
        #expect(
            throws: Alpha.PrivateDeploymentAbortDocument.ValidationError
                .unknownReason(0xFF)
        ) {
            _ = try Alpha.PrivateDeploymentAbortDocument.decode(
                from: unknownAbortReason,
                expectedPhase: .roleSelection,
                expectedContext: abortAuthority.context
            )
        }

        var relayEncoder = OpalFusion.Mosaic.CanonicalEncoder()
        try relayEncoder.writeText(
            Alpha.PrivateDeploymentNostrSelector.identifier
        )
        try relayEncoder.writeText(
            OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue
        )
        try relayEncoder.writeFixedBytes(
            Alpha.mainnetGenesisHash,
            byteCount: 32
        )
        try relayEncoder.writeVector(
            Array(formation.discovery.relaySet.registrations.reversed())
        ) { encoder, registration in
            try encoder.writeBytes(registration.canonicalBytes)
        }
        #expect(
            throws: OpalFusion.Mosaic.CanonicalCodingError
                .nonCanonicalSetOrdering
        ) {
            _ = try Alpha.RelaySetDocument.decode(
                from: relayEncoder.encodedBytes
            )
        }

        var acknowledgementSetEncoder = OpalFusion.Mosaic.CanonicalEncoder()
        try acknowledgementSetEncoder.writeText(
            Alpha.PrivateDeploymentNostrSelector.identifier
        )
        try acknowledgementSetEncoder.writeVector(
            Array(formation.acknowledgementSet.acknowledgements.reversed())
        ) { encoder, acknowledgement in
            try encoder.writeBytes(acknowledgement.canonicalBytes)
        }
        #expect(
            throws: Alpha.CandidateSetAcknowledgementSetDocument
                .ValidationError.nonCanonicalOrdering
        ) {
            _ = try Alpha.CandidateSetAcknowledgementSetDocument.decode(
                from: acknowledgementSetEncoder.encodedBytes,
                candidateSelection: formation.selection
            )
        }

        var allocationEncoder = OpalFusion.Mosaic.CanonicalEncoder()
        try allocationEncoder.writeText(
            Alpha.PrivateDeploymentNostrSelector.identifier
        )
        try allocationEncoder.writeText(
            OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue
        )
        try allocationEncoder.writeFixedBytes(
            Alpha.mainnetGenesisHash,
            byteCount: 32
        )
        try allocationEncoder.writeFixedBytes(
            formation.nonceAllocation.controlRosterDigest,
            byteCount: 32
        )
        try allocationEncoder.writeVector(
            Array(formation.nonceAllocation.allocations.reversed())
        ) { encoder, allocation in
            try encoder.writeFixedBytes(
                allocation.contributor.validatedBytes,
                byteCount: 32
            )
            try encoder.writeFixedBytes(allocation.publicSource, byteCount: 32)
        }
        #expect(
            throws: Alpha.ContributorNonceAllocationDocument.ValidationError
                .nonCanonicalOrdering
        ) {
            _ = try Alpha.ContributorNonceAllocationDocument.decode(
                from: allocationEncoder.encodedBytes,
                roleElection: formation.roleElection
            )
        }
    }

    @Test("Reject exact protocol and genesis drift in direct parsers")
    func rejectExactProtocolAndGenesisDriftInDirectParsers() async throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let manifest = try MosaicPrivateDeploymentFixtures
            .makeManifestValidation(formation: formation)
        let roundManifest = try MosaicPrivateDeploymentFixtures
            .makeRoundManifest(
                formation: formation,
                validation: manifest
            )
        let completed = try await MosaicMainnetAlphaBCHCompletionFixtures
            .prepare(manifest: roundManifest)
        let completionValidation = try Alpha
            .PrivateDeploymentCompletionValidation(
                manifest: manifest,
                roundManifest: roundManifest,
                completeTransactionValidation: completed.validation
            )
        let completion = Alpha.PrivateDeploymentCompletionDocument(
            validation: completionValidation
        )
        let signer = formation.roleElection.roster.controlIdentities[0]
        let abortAuthority = try Alpha.PrivateDeploymentAbortAuthority
            .makeRoleSelectionAuthority(
                participant: signer,
                controlRoster: formation.controlRoster
            )
        let abort = try Alpha.PrivateDeploymentAbortDocument(
            discoveryEpochStartUnixSeconds: formation.discovery.epochStart,
            phase: .roleSelection,
            context: abortAuthority.context,
            reason: .timeout
        )
        let payload = try Alpha.PreManifestNostrPayloadDocument
            .makeAvailabilityBeacon(formation.discovery.beacons[0])
        let acknowledgement = formation.acknowledgementSet
            .acknowledgements[0]
        let admission = formation.controlRoster.admissions[0]
        let selectorByteCount = Alpha.PrivateDeploymentNostrSelector
            .identifier.utf8.count
        let protocolIdentifierIndex = 4 + selectorByteCount + 4
        let genesisHashIndex = protocolIdentifierIndex
            + OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue.utf8.count
        let signedBodyStartIndex = 4 + selectorByteCount + 4
        let signedBodyProtocolIdentifierIndex = signedBodyStartIndex
            + protocolIdentifierIndex
        let signedBodyGenesisHashIndex = signedBodyStartIndex
            + genesisHashIndex

        let vectors: [ProtocolBindingParserVector] = [
            .init(
                name: "opaque pool",
                canonicalBytes: formation.discovery.pool.canonicalBytes,
                protocolIdentifierIndex: protocolIdentifierIndex,
                genesisHashIndex: genesisHashIndex,
                decodeCanonicalBytes: {
                    try Alpha.OpaquePoolDocument.decode(from: $0).canonicalBytes
                },
                matchesProtocolIdentifierError: {
                    ($0 as? Alpha.OpaquePoolDocument.ValidationError)
                        == .invalidProtocolIdentifier
                },
                matchesGenesisHashError: {
                    ($0 as? Alpha.OpaquePoolDocument.ValidationError)
                        == .invalidNetworkGenesisHash
                }
            ),
            .init(
                name: "relay set",
                canonicalBytes: formation.discovery.relaySet.canonicalBytes,
                protocolIdentifierIndex: protocolIdentifierIndex,
                genesisHashIndex: genesisHashIndex,
                decodeCanonicalBytes: {
                    try Alpha.RelaySetDocument.decode(from: $0).canonicalBytes
                },
                matchesProtocolIdentifierError: {
                    ($0 as? Alpha.RelaySetDocument.ValidationError)
                        == .invalidProtocolIdentifier
                },
                matchesGenesisHashError: {
                    ($0 as? Alpha.RelaySetDocument.ValidationError)
                        == .invalidNetworkGenesisHash
                }
            ),
            .init(
                name: "availability beacon core",
                canonicalBytes: formation.discovery.beacons[0].core.canonicalBytes,
                protocolIdentifierIndex: protocolIdentifierIndex,
                genesisHashIndex: genesisHashIndex,
                decodeCanonicalBytes: {
                    try Alpha.AvailabilityBeaconCoreDocument.decode(from: $0)
                        .canonicalBytes
                },
                matchesProtocolIdentifierError: {
                    ($0 as? Alpha.AvailabilityBeaconCoreDocument.ValidationError)
                        == .invalidProtocolIdentifier
                },
                matchesGenesisHashError: {
                    ($0 as? Alpha.AvailabilityBeaconCoreDocument.ValidationError)
                        == .invalidNetworkGenesisHash
                }
            ),
            .init(
                name: "candidate-set acknowledgement",
                canonicalBytes: acknowledgement.canonicalBytes,
                protocolIdentifierIndex: signedBodyProtocolIdentifierIndex,
                genesisHashIndex: signedBodyGenesisHashIndex,
                decodeCanonicalBytes: {
                    try Alpha.CandidateSetAcknowledgementDocument.decode(from: $0)
                        .canonicalBytes
                },
                matchesProtocolIdentifierError: {
                    ($0 as? Alpha.CandidateSetAcknowledgementDocument.ValidationError)
                        == .invalidProtocolIdentifier
                },
                matchesGenesisHashError: {
                    ($0 as? Alpha.CandidateSetAcknowledgementDocument.ValidationError)
                        == .invalidNetworkGenesisHash
                }
            ),
            .init(
                name: "candidate admission",
                canonicalBytes: admission.canonicalBytes,
                protocolIdentifierIndex: signedBodyProtocolIdentifierIndex,
                genesisHashIndex: signedBodyGenesisHashIndex,
                decodeCanonicalBytes: {
                    try Alpha.CandidateAdmissionDocument.decode(from: $0)
                        .canonicalBytes
                },
                matchesProtocolIdentifierError: {
                    ($0 as? Alpha.CandidateAdmissionDocument.ValidationError)
                        == .invalidProtocolIdentifier
                },
                matchesGenesisHashError: {
                    ($0 as? Alpha.CandidateAdmissionDocument.ValidationError)
                        == .invalidNetworkGenesisHash
                }
            ),
            .init(
                name: "contributor nonce allocation",
                canonicalBytes: formation.nonceAllocation.canonicalBytes,
                protocolIdentifierIndex: protocolIdentifierIndex,
                genesisHashIndex: genesisHashIndex,
                decodeCanonicalBytes: {
                    try Alpha.ContributorNonceAllocationDocument.decode(
                        from: $0,
                        roleElection: formation.roleElection
                    ).canonicalBytes
                },
                matchesProtocolIdentifierError: {
                    ($0 as? Alpha.ContributorNonceAllocationDocument.ValidationError)
                        == .invalidProtocolIdentifier
                },
                matchesGenesisHashError: {
                    ($0 as? Alpha.ContributorNonceAllocationDocument.ValidationError)
                        == .invalidNetworkGenesisHash
                }
            ),
            .init(
                name: "abort",
                canonicalBytes: abort.canonicalBytes,
                protocolIdentifierIndex: protocolIdentifierIndex,
                genesisHashIndex: genesisHashIndex,
                decodeCanonicalBytes: {
                    try Alpha.PrivateDeploymentAbortDocument.decode(
                        from: $0,
                        expectedPhase: .roleSelection,
                        expectedContext: abortAuthority.context
                    ).canonicalBytes
                },
                matchesProtocolIdentifierError: {
                    ($0 as? Alpha.PrivateDeploymentAbortDocument.ValidationError)
                        == .invalidProtocolIdentifier
                },
                matchesGenesisHashError: {
                    ($0 as? Alpha.PrivateDeploymentAbortDocument.ValidationError)
                        == .invalidNetworkGenesisHash
                }
            ),
            .init(
                name: "completion",
                canonicalBytes: completion.canonicalBytes,
                protocolIdentifierIndex: protocolIdentifierIndex,
                genesisHashIndex: genesisHashIndex,
                decodeCanonicalBytes: {
                    try Alpha.PrivateDeploymentCompletionDocument.decode(
                        from: $0,
                        validation: completionValidation
                    ).canonicalBytes
                },
                matchesProtocolIdentifierError: {
                    ($0 as? Alpha.PrivateDeploymentCompletionDocument.ValidationError)
                        == .invalidProtocolIdentifier
                },
                matchesGenesisHashError: {
                    ($0 as? Alpha.PrivateDeploymentCompletionDocument.ValidationError)
                        == .invalidNetworkGenesisHash
                }
            ),
            .init(
                name: "Nostr payload",
                canonicalBytes: payload.canonicalBytes,
                protocolIdentifierIndex: protocolIdentifierIndex,
                genesisHashIndex: genesisHashIndex,
                decodeCanonicalBytes: {
                    try Alpha.PreManifestNostrPayloadDocument.decode(from: $0)
                        .canonicalBytes
                },
                matchesProtocolIdentifierError: {
                    ($0 as? Alpha.PreManifestNostrPayloadDocument.ValidationError)
                        == .invalidProtocolIdentifier
                },
                matchesGenesisHashError: {
                    ($0 as? Alpha.PreManifestNostrPayloadDocument.ValidationError)
                        == .invalidNetworkGenesisHash
                }
            ),
        ]

        for vector in vectors {
            expectProtocolBindingRejection(
                of: protocolIdentifierDrift(
                    in: vector.canonicalBytes,
                    at: vector.protocolIdentifierIndex
                ),
                vector: vector,
                fieldName: "protocol identifier",
                matchesExpectedError: vector.matchesProtocolIdentifierError
            )
            expectProtocolBindingRejection(
                of: genesisHashDrift(
                    in: vector.canonicalBytes,
                    at: vector.genesisHashIndex
                ),
                vector: vector,
                fieldName: "genesis hash",
                matchesExpectedError: vector.matchesGenesisHashError
            )
        }
    }

    private func truncationCounts(for byteCount: Int) -> [Int] {
        Array(Set([0, 1, byteCount / 3, byteCount / 2, byteCount - 1]))
            .filter { $0 >= 0 && $0 < byteCount }
            .sorted()
    }

    private func mutationIndices(for byteCount: Int) -> [Int] {
        Array(Set([4, byteCount / 4, byteCount / 2, byteCount * 3 / 4,
                   byteCount - 1]))
            .filter { $0 >= 0 && $0 < byteCount }
            .sorted()
    }

    private func protocolIdentifierDrift(
        in canonicalBytes: [UInt8],
        at protocolIdentifierIndex: Int
    ) -> [UInt8] {
        var driftedBytes = canonicalBytes
        let expectedIdentifier = Array(
            OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue.utf8
        )
        #expect(
            Array(
                canonicalBytes[
                    protocolIdentifierIndex ..< protocolIdentifierIndex
                        + expectedIdentifier.count
                ]
            ) == expectedIdentifier
        )
        driftedBytes[protocolIdentifierIndex] ^= 0x01
        return driftedBytes
    }

    private func genesisHashDrift(
        in canonicalBytes: [UInt8],
        at genesisHashIndex: Int
    ) -> [UInt8] {
        var driftedBytes = canonicalBytes
        #expect(
            Array(canonicalBytes[genesisHashIndex ..< genesisHashIndex + 32])
                == Alpha.mainnetGenesisHash
        )
        driftedBytes[genesisHashIndex] ^= 0x01
        return driftedBytes
    }

    private func expectProtocolBindingRejection(
        of encodedBytes: [UInt8],
        vector: ProtocolBindingParserVector,
        fieldName: String,
        matchesExpectedError: (any Error) -> Bool
    ) {
        do {
            _ = try vector.decodeCanonicalBytes(encodedBytes)
            Issue.record("Accepted \(fieldName) drift in \(vector.name)")
        } catch {
            #expect(
                matchesExpectedError(error),
                "Unexpected \(fieldName) error in \(vector.name): \(error)"
            )
        }
    }
}
