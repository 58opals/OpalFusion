// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentContext.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Canonicalizes one fresh pool identifier and the exact reviewed three-relay policy.
    @_spi(MosaicPrivateAlpha)
    public static func makePrivateDeploymentContextDocuments(
        opaquePoolIdentifier: Data,
        relayRegistrations: [PrivateDeploymentRelayRegistration]
    ) throws -> PrivateDeploymentContextDocuments {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha

        let pool: Alpha.OpaquePoolDocument
        do {
            pool = try .init(
                appGeneratedOpaqueIdentifier: Array(opaquePoolIdentifier)
            )
        } catch {
            throw PrivateDeploymentConfigurationFailure
                .invalidOpaquePoolIdentifier
        }

        guard relayRegistrations.count == Alpha.relayCount else {
            throw PrivateDeploymentConfigurationFailure.invalidRelayCount
        }

        var registrations: [Alpha.RelayRegistrationDocument] = []
        registrations.reserveCapacity(relayRegistrations.count)
        for registration in relayRegistrations {
            guard !registration.requiresNIP42Authentication else {
                throw PrivateDeploymentConfigurationFailure
                    .unsupportedNIP42Authentication
            }
            guard !registration.requiresProofOfWork else {
                throw PrivateDeploymentConfigurationFailure
                    .unsupportedProofOfWork
            }

            let endpoint: Alpha.PrivateRelayEndpoint
            do {
                endpoint = try .init(normalizing: registration.endpoint)
            } catch {
                throw PrivateDeploymentConfigurationFailure
                    .invalidRelayEndpoint
            }

            let operatorIdentity: Alpha.RelayOperatorIdentity
            do {
                operatorIdentity = try .init(
                    appReviewedRegistryLabel:
                        registration.reviewedOperatorRegistryLabel
                )
            } catch {
                throw PrivateDeploymentConfigurationFailure
                    .invalidOperatorRegistryLabel
            }

            do {
                registrations.append(
                    try .init(
                        endpoint: endpoint,
                        operatorIdentity: operatorIdentity,
                        requiresNIP42Authentication: false,
                        requiresProofOfWork: false
                    )
                )
            } catch {
                throw PrivateDeploymentConfigurationFailure
                    .invalidRelayEndpoint
            }
        }

        let relaySet: Alpha.RelaySetDocument
        do {
            relaySet = try .init(registrations: registrations)
        } catch let failure {
            switch failure {
            case .invalidRelayCount:
                throw PrivateDeploymentConfigurationFailure.invalidRelayCount
            case .duplicateEndpoint:
                throw PrivateDeploymentConfigurationFailure
                    .duplicateRelayEndpoint
            case .duplicateOperator:
                throw PrivateDeploymentConfigurationFailure
                    .duplicateRelayOperator
            case .invalidSelector, .invalidProtocolIdentifier,
                 .invalidNetworkGenesisHash, .manifestDigestMismatch:
                throw PrivateDeploymentConfigurationFailure
                    .invalidRelayEndpoint
            }
        }

        return .init(
            opaquePoolDocument: Data(pool.canonicalBytes),
            relaySetDocument: Data(relaySet.canonicalBytes),
            relaySetDigest: Data(relaySet.digest),
            relayEndpointIdentifiers: relaySet.registrations.map {
                $0.endpoint.normalizedURL
            }
        )
    }
}
#endif
