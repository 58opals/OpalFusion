// OpalFusion+Mosaic+Attempt+ManifestAgreement.swift

extension OpalFusion.Mosaic.Attempt {
    /// A unanimous manifest result bound to one immutable role-selected roster.
    struct ManifestAgreement: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case unknownSigner(ControlIdentity)
            case duplicateSigner(ControlIdentity)
            case bindingDisagreement
            case missingSigners([ControlIdentity])
        }

        let binding: ManifestBinding

        init(
            roster: Roster,
            validatedSignatures: [ManifestSignatureValidation]
        ) throws(ValidationError) {
            let expectedSigners = Set(roster.controlIdentities)
            var recordedSigners: Set<ControlIdentity> = []
            var commonBinding: ManifestBinding?

            for validation in validatedSignatures {
                guard expectedSigners.contains(validation.signer) else {
                    throw ValidationError.unknownSigner(validation.signer)
                }
                guard recordedSigners.insert(validation.signer).inserted else {
                    throw ValidationError.duplicateSigner(validation.signer)
                }
                if let commonBinding {
                    guard validation.binding == commonBinding else {
                        throw ValidationError.bindingDisagreement
                    }
                } else {
                    commonBinding = validation.binding
                }
            }

            let missingSigners = roster.controlIdentities.filter {
                !recordedSigners.contains($0)
            }
            guard missingSigners.isEmpty else {
                throw ValidationError.missingSigners(missingSigners)
            }
            guard let commonBinding else {
                preconditionFailure("A validated Mosaic roster is never empty.")
            }

            self.binding = commonBinding
        }
    }
}
