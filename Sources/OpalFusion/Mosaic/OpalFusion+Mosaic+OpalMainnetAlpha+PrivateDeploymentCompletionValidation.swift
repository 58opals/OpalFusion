// OpalFusion+Mosaic+OpalMainnetAlpha+PrivateDeploymentCompletionValidation.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Proof that a previous-output-validated transaction completes one fully signed manifest.
    struct PrivateDeploymentCompletionValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case manifestCoreMismatch
            case manifestBindingMismatch
            case completeTransactionMismatch
        }

        let manifest: PrivateDeploymentManifestValidation
        let roundManifest: RoundManifest
        let completeTransactionValidation: CompleteTransactionValidation

        var completedPayload: CompleteTransactionPayload {
            completeTransactionValidation.candidate.payload
        }

        init(
            manifest: PrivateDeploymentManifestValidation,
            roundManifest: RoundManifest,
            completeTransactionValidation: CompleteTransactionValidation
        ) throws(ValidationError) {
            guard roundManifest.core == manifest.core else {
                throw .manifestCoreMismatch
            }
            guard completeTransactionValidation.candidate.transcript.manifest
                    == roundManifest.binding else {
                throw .manifestBindingMismatch
            }
            guard completeTransactionValidation.completeTransaction
                    == completeTransactionValidation.candidate.payload
                        .completeTransaction else {
                throw .completeTransactionMismatch
            }
            self.manifest = manifest
            self.roundManifest = roundManifest
            self.completeTransactionValidation = completeTransactionValidation
        }
    }
}
