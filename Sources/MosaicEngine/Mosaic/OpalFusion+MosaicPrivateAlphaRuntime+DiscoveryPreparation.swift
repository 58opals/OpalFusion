import OpalFusionCore

// OpalFusion+MosaicPrivateAlphaRuntime+DiscoveryPreparation.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Public, non-custodial inputs to one private discovery epoch.
    ///
    /// The application supplies a fresh deployment-scoped pool identifier and reviewed
    /// relay operator labels. Distinct labels do not prove operator independence.
    @_spi(MosaicPrivateAlpha)
    public struct DiscoveryPreparation: Sendable {
        private typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha

        @_spi(MosaicPrivateAlpha)
        public struct Relay: Sendable, Equatable {
            @_spi(MosaicPrivateAlpha) public let endpoint: String
            @_spi(MosaicPrivateAlpha) public let reviewedOperatorLabel: String

            @_spi(MosaicPrivateAlpha)
            public init(endpoint: String, reviewedOperatorLabel: String) {
                self.endpoint = endpoint
                self.reviewedOperatorLabel = reviewedOperatorLabel
            }
        }

        /// Explicit versioned deployment choice; never negotiated or inferred.
        @_spi(MosaicPrivateAlpha)
        public enum TimingProfile: String, Sendable, Equatable {
            case frozen = "nostr-tor/0-opal-mainnet-alpha-private-deployment.1"
            case bootstrap180Candidate = "nostr-tor/0-opal-mainnet-alpha-private-deployment-bootstrap180.1"

            var policy: OpalFusion.Mosaic.OpalMainnetAlpha.PrivateDeploymentPolicy {
                switch self {
                case .frozen: .frozen
                case .bootstrap180Candidate: .bootstrap180Candidate
                }
            }
        }

        @_spi(MosaicPrivateAlpha)
        public enum PreparationFailure: Error, Sendable, Equatable {
            case invalidSearchRange
        }

        @_spi(MosaicPrivateAlpha) public let epochStartUnixSeconds: UInt64
        @_spi(MosaicPrivateAlpha) public let opaquePoolDocument: Data
        @_spi(MosaicPrivateAlpha) public let relaySetDocument: Data
        @_spi(MosaicPrivateAlpha) public let relaySetDigest: Data
        @_spi(MosaicPrivateAlpha) public let relayEndpointIdentifiers: [String]
        @_spi(MosaicPrivateAlpha) public let relayOperatorDigests: [Data]
        @_spi(MosaicPrivateAlpha) public let beaconCutoffUnixSeconds: UInt64
        private let pool: Alpha.OpaquePoolDocument

        @_spi(MosaicPrivateAlpha)
        public init(
            epochStartUnixSeconds: UInt64,
            appGeneratedOpaquePoolIdentifier: Data,
            relays: [Relay],
            timingProfile: TimingProfile = .frozen
        ) throws {
            let deadlines = try Alpha.PrivateDeploymentPolicy.frozen
                .preManifestDeadlines(forEpochStartingAt: epochStartUnixSeconds)
            let documents = try OpalFusion.MosaicPrivateAlphaRuntime
                .makePrivateDeploymentContextDocuments(
                    opaquePoolIdentifier: appGeneratedOpaquePoolIdentifier,
                    timingProfile: timingProfile,
                    relayRegistrations: relays.map {
                        .init(
                            endpoint: $0.endpoint,
                            reviewedOperatorRegistryLabel: $0.reviewedOperatorLabel,
                            requiresNIP42Authentication: false,
                            requiresProofOfWork: false
                        )
                    }
                )
            let pool = try Alpha.OpaquePoolDocument(
                appGeneratedOpaqueIdentifier: Array(appGeneratedOpaquePoolIdentifier),
                policy: timingProfile.policy
            )
            let relaySet = try Alpha.RelaySetDocument.decode(
                from: Array(documents.relaySetDocument)
            )
            self.epochStartUnixSeconds = epochStartUnixSeconds
            self.pool = pool
            opaquePoolDocument = documents.opaquePoolDocument
            relaySetDocument = documents.relaySetDocument
            relaySetDigest = documents.relaySetDigest
            relayEndpointIdentifiers = documents.relayEndpointIdentifiers
            relayOperatorDigests = relaySet.registrations.map { Data($0.operatorIdentity.canonicalDigest) }
            beaconCutoffUnixSeconds = deadlines.beaconCutoff
        }

        /// Searches at most 65,536 nonces using the frozen protocol's work validator.
        /// Callers schedule batches off the UI actor and check cancellation between batches.
        /// No key, signature, network, wallet, or persistent state is accessed here.
        @_spi(MosaicPrivateAlpha)
        public func findAvailabilityNonce(
            discoveryVerificationKey: OpalCrypto.Signature.BIP340.VerificationKey,
            startingAt firstNonce: UInt64,
            count: UInt32
        ) throws -> UInt64? {
            guard (1 ... 65_536).contains(count),
                  !firstNonce.addingReportingOverflow(UInt64(count) - 1).overflow else {
                throw PreparationFailure.invalidSearchRange
            }
            for offset in 0 ..< UInt64(count) {
                let nonce = firstNonce + offset
                let core = try Alpha.AvailabilityBeaconCoreDocument(
                    discoveryEpochStartUnixSeconds: epochStartUnixSeconds,
                    opaquePoolIdentifier: pool.opaqueIdentifier,
                    discoveryIdentity: discoveryVerificationKey,
                    relaySetDigest: Array(relaySetDigest),
                    proofOfWorkNonce: nonce,
                    expiryUnixSeconds: beaconCutoffUnixSeconds
                )
                if (try? Alpha.AvailabilityBeaconDocument.validateWork(for: core)) != nil {
                    return nonce
                }
            }
            return nil
        }
    }
}
#endif
