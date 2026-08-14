// OpalFusion+Mosaic+OpalMainnetAlpha+PrivateDeploymentManifestSignatureValidation.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// A canonical raw manifest signature retained beside its successful validation.
    struct PrivateDeploymentManifestSignatureValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case signerNotInRoster
            case invalidSignature(
                OpalFusion.Mosaic.Attempt.ManifestSignatureValidation
                    .ValidationError
            )
        }

        let signature: OpalFusion.Mosaic.Attempt.ManifestSignature
        let validation: OpalFusion.Mosaic.Attempt.ManifestSignatureValidation

        init(
            validating signature: OpalFusion.Mosaic.Attempt.ManifestSignature,
            for binding: OpalFusion.Mosaic.Attempt.ManifestBinding,
            expectedRoster: OpalFusion.Mosaic.Attempt.Roster
        ) throws(ValidationError) {
            guard expectedRoster.controlIdentities.contains(signature.signer) else {
                throw .signerNotInRoster
            }
            let validation: OpalFusion.Mosaic.Attempt.ManifestSignatureValidation
            do {
                validation = try .init(validating: signature, for: binding)
            } catch {
                throw .invalidSignature(error)
            }
            self.signature = signature
            self.validation = validation
        }
    }
}
