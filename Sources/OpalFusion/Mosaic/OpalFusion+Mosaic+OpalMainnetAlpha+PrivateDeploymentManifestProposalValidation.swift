// OpalFusion+Mosaic+OpalMainnetAlpha+PrivateDeploymentManifestProposalValidation.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Proof that the selector-bound proposal body and signature context come from one validated formation.
    struct PrivateDeploymentManifestProposalValidation: Sendable, Equatable {
        let manifest: PrivateDeploymentManifestValidation
        let expectedContext: ManifestProposalContext
        let canonicalBody: [UInt8]
        let signatureBinding: OpalFusion.Mosaic.Attempt.ManifestBinding

        init(manifest: PrivateDeploymentManifestValidation) throws {
            let context = try ManifestProposalContext(
                roleElection: manifest.roleElection,
                candidateSetDigest: manifest.candidateSelection
                    .candidateSetDigest,
                opaquePoolIdentifier: manifest.opaquePool.opaqueIdentifier
            )
            let body = try PreManifestDocumentCodec.encodeManifestProposal(
                manifest.core
            )
            let decoded = try PreManifestDocumentCodec.decodeManifestProposal(
                from: body,
                expectedContext: context
            )
            guard decoded == manifest.core else {
                throw ContractError.rosterMismatch
            }
            let proposalDigest = RoleSeedValidator.hash(
                domainSuffix: "private-deployment/manifest-proposal",
                fields: [
                    PrivateDeploymentNostrSelector.identifierBytes,
                    body,
                ]
            )
            let binding = try OpalFusion.Mosaic.Attempt.ManifestBinding(
                validatedRoundIdentifier: manifest.core.roundIdentifier,
                validatedManifestDigest: proposalDigest
            )
            self.manifest = manifest
            expectedContext = context
            canonicalBody = body
            signatureBinding = binding
        }
    }
}
