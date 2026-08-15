// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentProof.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Opaque package-minted proof of one complete private-deployment formation.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentProof: Equatable, Sendable {
        let validatedAttempt: OpalFusion.Mosaic.Attempt
        let proposalValidation: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentManifestProposalValidation
        let completeManifest: OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifest
        let canonicalDocuments: [Data]

        @_spi(MosaicPrivateAlpha)
        public var discoveryEpochStartUnixSeconds: UInt64 {
            proposalValidation.manifest.discoveryEpochStartUnixSeconds
        }

        @_spi(MosaicPrivateAlpha)
        public var controlIdentities: [Data] {
            completeManifest.core.roster.controlIdentities.map {
                Data($0.validatedBytes)
            }
        }

        init(
            validatedAttempt: OpalFusion.Mosaic.Attempt,
            proposalValidation: OpalFusion.Mosaic.OpalMainnetAlpha
                .PrivateDeploymentManifestProposalValidation,
            completeManifest: OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifest,
            canonicalDocuments: [Data]
        ) {
            self.validatedAttempt = validatedAttempt
            self.proposalValidation = proposalValidation
            self.completeManifest = completeManifest
            self.canonicalDocuments = canonicalDocuments
        }

        public static func == (
            lhs: Self,
            rhs: Self
        ) -> Bool {
            lhs.canonicalDocuments == rhs.canonicalDocuments
        }
    }
}
#endif
