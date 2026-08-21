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

        @_spi(MosaicPrivateAlpha)
        public var preManifestEventIdentities: [Data] {
            let discovery = proposalValidation.manifest
                .candidateSelection.selectedDiscoveryIdentities.map(Data.init)
            return Array(Set(discovery + controlIdentities)).sorted {
                $0.lexicographicallyPrecedes($1)
            }
        }

        @_spi(MosaicPrivateAlpha)
        public var conductorControlIdentity: Data {
            Data(completeManifest.core.roster.conductor.validatedBytes)
        }

        @_spi(MosaicPrivateAlpha)
        public var contributorControlIdentities: [Data] {
            completeManifest.core.roster.contributors.map {
                Data($0.validatedBytes)
            }
        }

        @_spi(MosaicPrivateAlpha)
        public var roundIdentifier: Data {
            Data(completeManifest.core.roundIdentifier)
        }

        @_spi(MosaicPrivateAlpha)
        public var relaySetDigest: Data {
            Data(completeManifest.core.relaySetDigest)
        }

        @_spi(MosaicPrivateAlpha)
        public var relayEndpointIdentifiers: [String] {
            proposalValidation.manifest.relaySet.registrations.map {
                $0.endpoint.normalizedURL
            }
        }

        @_spi(MosaicPrivateAlpha)
        public var phaseStartUnixSeconds: UInt64 {
            completeManifest.core.deadlines.phaseStart
        }

        @_spi(MosaicPrivateAlpha)
        public var walletReservationDeadlineUnixSeconds: UInt64 {
            completeManifest.core.deadlines.walletReservation
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
