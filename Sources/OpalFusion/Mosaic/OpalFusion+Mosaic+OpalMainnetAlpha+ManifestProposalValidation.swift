// OpalFusion+Mosaic+OpalMainnetAlpha+ManifestProposalValidation.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// The exact locally accepted manifest core and its pre-manifest context.
    ///
    /// A complete manifest admitted later must contain this exact core. The value does not choose
    /// transport timing, a control-sequence epoch, or any wire identifier.
    struct ManifestProposalValidation: Sendable, Equatable {
        let context: ManifestProposalContext
        let core: RoundManifestCore

        init(
            validating core: RoundManifestCore,
            against context: ManifestProposalContext
        ) throws {
            try core.validateProposal(against: context)
            self.context = context
            self.core = core
        }
    }
}
