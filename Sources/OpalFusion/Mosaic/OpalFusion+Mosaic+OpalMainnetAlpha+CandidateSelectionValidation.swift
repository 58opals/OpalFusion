// OpalFusion+Mosaic+OpalMainnetAlpha+CandidateSelectionValidation.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Deterministic seven-to-nine candidate selection for one private discovery context.
    struct CandidateSelectionValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case epochMismatch
            case poolMismatch
            case relaySetMismatch
            case discoveryIdentityEquivocation([UInt8])
            case insufficientCandidateCount(actual: Int)
        }

        let discoveryEpochStartUnixSeconds: UInt64
        let opaquePoolIdentifier: [UInt8]
        let relaySetDigest: [UInt8]
        let selectedBeacons: [AvailabilityBeaconDocument]
        let candidateSetDigest: [UInt8]

        var canonicalCandidateSetBytes: [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                try encoder.writeVector(selectedBeacons) { encoder, beacon in
                    try encoder.writeBytes(beacon.canonicalBodyBytes)
                }
                return encoder.encodedBytes
            } catch {
                preconditionFailure("A validated candidate selection must encode.")
            }
        }

        var selectedDiscoveryIdentities: [[UInt8]] {
            selectedBeacons.map {
                [UInt8]($0.core.discoveryIdentity.rawRepresentation)
            }
        }

        init(
            beacons: [AvailabilityBeaconDocument],
            discoveryEpochStartUnixSeconds: UInt64,
            opaquePool: OpaquePoolDocument,
            relaySet: RelaySetDocument
        ) throws(ValidationError) {
            var beaconsByIdentity: [Data: AvailabilityBeaconDocument] = [:]
            for beacon in beacons {
                guard beacon.core.discoveryEpochStartUnixSeconds
                        == discoveryEpochStartUnixSeconds else {
                    throw .epochMismatch
                }
                guard beacon.core.opaquePoolIdentifier
                        == opaquePool.opaqueIdentifier else {
                    throw .poolMismatch
                }
                guard beacon.core.relaySetDigest == relaySet.digest else {
                    throw .relaySetMismatch
                }
                let identity = beacon.core.discoveryIdentity.rawRepresentation
                if let existing = beaconsByIdentity[identity] {
                    guard existing.core.canonicalBytes
                            == beacon.core.canonicalBytes else {
                        throw .discoveryIdentityEquivocation([UInt8](identity))
                    }
                    if beacon.canonicalBytes.lexicographicallyPrecedes(
                        existing.canonicalBytes
                    ) {
                        beaconsByIdentity[identity] = beacon
                    }
                    continue
                }
                beaconsByIdentity[identity] = beacon
            }
            guard beaconsByIdentity.count >= 7 else {
                throw .insufficientCandidateCount(actual: beaconsByIdentity.count)
            }
            let selected = beaconsByIdentity.values.sorted { lhs, rhs in
                if lhs.core.workDigest != rhs.core.workDigest {
                    return lhs.core.workDigest.lexicographicallyPrecedes(
                        rhs.core.workDigest
                    )
                }
                return lhs.core.discoveryIdentity.rawRepresentation
                    .lexicographicallyPrecedes(
                        rhs.core.discoveryIdentity.rawRepresentation
                    )
            }.prefix(9)
            self.discoveryEpochStartUnixSeconds = discoveryEpochStartUnixSeconds
            self.opaquePoolIdentifier = opaquePool.opaqueIdentifier
            self.relaySetDigest = relaySet.digest
            self.selectedBeacons = Array(selected)

            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                try encoder.writeVector(Array(selected)) { encoder, beacon in
                    try encoder.writeBytes(beacon.canonicalBodyBytes)
                }
            } catch {
                preconditionFailure("A validated candidate selection must encode.")
            }
            candidateSetDigest = RoleSeedValidator.hash(
                domainSuffix: "private-deployment/candidate-set",
                fields: [
                    PrivateDeploymentNostrSelector.identifierBytes,
                    encoder.encodedBytes,
                ]
            )
        }
    }
}
