// OpalFusion+Mosaic+OpalMainnetAlpha+ControlRosterValidation.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Complete candidate-admission validation and canonical control-roster digest.
    struct ControlRosterValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case unknownDiscoveryIdentity([UInt8])
            case duplicateDiscoveryIdentity([UInt8])
            case duplicateControlIdentity([UInt8])
            case discoveryControlIdentityOverlap([UInt8])
            case candidateSetDigestMismatch([UInt8])
            case discoveryEpochMismatch([UInt8])
            case missingAdmissions([[UInt8]])
            case acknowledgementSetMismatch
            case controlRosterBindingRejected
        }

        let discoveryEpochStartUnixSeconds: UInt64
        let candidateSetDigest: [UInt8]
        let admissions: [CandidateAdmissionDocument]
        let controlRosterDigest: [UInt8]
        let controlRosterBinding: OpalFusion.Mosaic.Attempt.ControlRosterBinding

        var canonicalAdmissionBytes: [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                try encoder.writeVector(admissions) { encoder, admission in
                    try encoder.writeBytes(admission.canonicalBytes)
                }
                return encoder.encodedBytes
            } catch {
                preconditionFailure("Validated candidate admissions must encode.")
            }
        }

        init(
            admissions: [CandidateAdmissionDocument],
            candidateSelection: CandidateSelectionValidation,
            acknowledgementSet: CandidateSetAcknowledgementSetDocument
        ) throws(ValidationError) {
            guard acknowledgementSet.discoveryEpochStartUnixSeconds
                    == candidateSelection.discoveryEpochStartUnixSeconds,
                  acknowledgementSet.candidateSetDigest
                    == candidateSelection.candidateSetDigest,
                  Set(acknowledgementSet.acknowledgements.map {
                      Data($0.signerDiscoveryIdentity.rawRepresentation)
                  }) == Set(candidateSelection.selectedDiscoveryIdentities.map {
                      Data($0)
                  }) else {
                throw .acknowledgementSetMismatch
            }
            let expectedDiscoveryIdentities = Set(
                candidateSelection.selectedDiscoveryIdentities.map {
                    Data($0)
                }
            )
            var admissionsByDiscoveryIdentity: [
                Data: CandidateAdmissionDocument
            ] = [:]
            var controlIdentities: Set<Data> = []
            for admission in admissions {
                let discoveryIdentity = admission.discoveryIdentity.rawRepresentation
                guard expectedDiscoveryIdentities.contains(discoveryIdentity) else {
                    throw .unknownDiscoveryIdentity([UInt8](discoveryIdentity))
                }
                guard admissionsByDiscoveryIdentity[discoveryIdentity] == nil else {
                    throw .duplicateDiscoveryIdentity([UInt8](discoveryIdentity))
                }
                let controlIdentity = Data(admission.controlIdentity.validatedBytes)
                guard controlIdentities.insert(controlIdentity).inserted else {
                    throw .duplicateControlIdentity([UInt8](controlIdentity))
                }
                guard !expectedDiscoveryIdentities.contains(controlIdentity) else {
                    throw .discoveryControlIdentityOverlap([UInt8](controlIdentity))
                }
                guard admission.candidateSetDigest
                        == candidateSelection.candidateSetDigest else {
                    throw .candidateSetDigestMismatch([UInt8](discoveryIdentity))
                }
                guard admission.discoveryEpochStartUnixSeconds
                        == candidateSelection.discoveryEpochStartUnixSeconds else {
                    throw .discoveryEpochMismatch([UInt8](discoveryIdentity))
                }
                admissionsByDiscoveryIdentity[discoveryIdentity] = admission
            }
            let missingAdmissions = expectedDiscoveryIdentities
                .subtracting(admissionsByDiscoveryIdentity.keys)
                .map { [UInt8]($0) }
                .sorted { $0.lexicographicallyPrecedes($1) }
            guard missingAdmissions.isEmpty else {
                throw .missingAdmissions(missingAdmissions)
            }
            let normalizedAdmissions = admissions.sorted {
                $0.discoveryIdentity.rawRepresentation.lexicographicallyPrecedes(
                    $1.discoveryIdentity.rawRepresentation
                )
            }
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                try encoder.writeVector(normalizedAdmissions) { encoder, admission in
                    try encoder.writeBytes(admission.canonicalBytes)
                }
            } catch {
                preconditionFailure("Validated candidate admissions must encode.")
            }
            let digest = RoleSeedValidator.hash(
                domainSuffix: "private-deployment/control-roster",
                fields: [
                    PrivateDeploymentNostrSelector.identifierBytes,
                    candidateSelection.candidateSetDigest,
                    encoder.encodedBytes
                ]
            )
            let binding: OpalFusion.Mosaic.Attempt.ControlRosterBinding
            do {
                binding = try .init(
                    validatedControlIdentities: normalizedAdmissions.map(\.controlIdentity),
                    validatedControlRosterDigest: digest
                )
            } catch {
                throw .controlRosterBindingRejected
            }
            discoveryEpochStartUnixSeconds =
                candidateSelection.discoveryEpochStartUnixSeconds
            candidateSetDigest = candidateSelection.candidateSetDigest
            self.admissions = normalizedAdmissions
            self.controlRosterDigest = digest
            self.controlRosterBinding = binding
        }
    }
}
