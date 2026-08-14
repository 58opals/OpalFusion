// OpalFusion+Mosaic+OpalMainnetAlpha+CandidateSetAcknowledgementSetDocument.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Complete canonical acknowledgement set for every selected discovery identity.
    struct CandidateSetAcknowledgementSetDocument: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidSelector
            case unknownSigner([UInt8])
            case duplicateSigner([UInt8])
            case candidateSetDigestMismatch([UInt8])
            case discoveryEpochMismatch([UInt8])
            case missingSigners([[UInt8]])
            case nonCanonicalOrdering
        }

        let discoveryEpochStartUnixSeconds: UInt64
        let candidateSetDigest: [UInt8]
        let acknowledgements: [CandidateSetAcknowledgementDocument]

        var canonicalBytes: [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            do {
                try encoder.writeText(PrivateDeploymentNostrSelector.identifier)
                try encoder.writeVector(acknowledgements) { encoder, acknowledgement in
                    try encoder.writeBytes(acknowledgement.canonicalBytes)
                }
                return encoder.encodedBytes
            } catch {
                preconditionFailure("A validated acknowledgement set must encode.")
            }
        }

        init(
            acknowledgements: [CandidateSetAcknowledgementDocument],
            candidateSelection: CandidateSelectionValidation
        ) throws(ValidationError) {
            let expectedSigners = Set(
                candidateSelection.selectedDiscoveryIdentities.map(Data.init)
            )
            var acknowledgementsBySigner: [
                Data: CandidateSetAcknowledgementDocument
            ] = [:]
            for acknowledgement in acknowledgements {
                let signer = acknowledgement.signerDiscoveryIdentity.rawRepresentation
                guard expectedSigners.contains(signer) else {
                    throw .unknownSigner([UInt8](signer))
                }
                guard acknowledgementsBySigner[signer] == nil else {
                    throw .duplicateSigner([UInt8](signer))
                }
                guard acknowledgement.candidateSetDigest
                        == candidateSelection.candidateSetDigest else {
                    throw .candidateSetDigestMismatch([UInt8](signer))
                }
                guard acknowledgement.discoveryEpochStartUnixSeconds
                        == candidateSelection.discoveryEpochStartUnixSeconds else {
                    throw .discoveryEpochMismatch([UInt8](signer))
                }
                acknowledgementsBySigner[signer] = acknowledgement
            }
            let missingSigners = expectedSigners
                .subtracting(acknowledgementsBySigner.keys)
                .map { [UInt8]($0) }
                .sorted { $0.lexicographicallyPrecedes($1) }
            guard missingSigners.isEmpty else {
                throw .missingSigners(missingSigners)
            }
            self.discoveryEpochStartUnixSeconds =
                candidateSelection.discoveryEpochStartUnixSeconds
            self.candidateSetDigest = candidateSelection.candidateSetDigest
            self.acknowledgements = acknowledgements.sorted {
                $0.signerDiscoveryIdentity.rawRepresentation.lexicographicallyPrecedes(
                    $1.signerDiscoveryIdentity.rawRepresentation
                )
            }
        }

        static func decode(
            from encodedBytes: [UInt8],
            candidateSelection: CandidateSelectionValidation
        ) throws -> Self {
            try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: encodedBytes
            ) { decoder in
                guard try decoder.readText()
                        == PrivateDeploymentNostrSelector.identifier else {
                    throw ValidationError.invalidSelector
                }
                let encodedAcknowledgements = try decoder.readVector { decoder in
                    try decoder.readBytes()
                }
                let acknowledgements = try encodedAcknowledgements.map {
                    try CandidateSetAcknowledgementDocument.decode(from: $0)
                }
                let document = try Self(
                    acknowledgements: acknowledgements,
                    candidateSelection: candidateSelection
                )
                guard document.acknowledgements == acknowledgements else {
                    throw ValidationError.nonCanonicalOrdering
                }
                return document
            }
        }
    }
}
