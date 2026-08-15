// OpalFusion+MosaicPrivateAlphaRuntime+RelaySelectionValidator.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    struct RelaySelectionValidator: OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestRelaySelectionValidating {
        let manifestRelaySetDigest: [UInt8]
        let endpointIdentifiers: [String]

        func validateRelaySelection(
            manifestRelaySetDigest: [UInt8],
            endpoints: [OpalFusion.Mosaic.OpalMainnetAlpha
                .PostManifestRelayEndpoint]
        ) throws {
            guard manifestRelaySetDigest == self.manifestRelaySetDigest,
                  endpoints.map(\.validatedIdentifier)
                    == endpointIdentifiers else {
                throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                    .invalidPrivateDeploymentProof
            }
        }
    }
}
#endif
