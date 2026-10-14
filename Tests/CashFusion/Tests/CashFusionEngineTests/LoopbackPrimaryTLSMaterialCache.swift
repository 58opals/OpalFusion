// LoopbackPrimaryTLSMaterialCache.swift

import Foundation
import Network
import Security

actor LoopbackPrimaryTLSMaterialCache {
    private var materialResult: Result<
        LoopbackPrimaryTLSTestFixture.Material,
        LiveRuntimeTestHarnessError
    >?

    func loadTrustAnchorCertificateDERs() throws -> [Data] {
        [try loadMaterial().certificateDER]
    }

    func makeListenerParameters() throws -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(
            tlsOptions.securityProtocolOptions,
            try loadMaterial().localIdentity
        )

        return NWParameters(
            tls: tlsOptions,
            tcp: NWProtocolTCP.Options()
        )
    }

    private func loadMaterial() throws -> LoopbackPrimaryTLSTestFixture.Material {
        if let materialResult {
            switch materialResult {
            case let .success(material):
                return material
            case let .failure(error):
                throw error
            }
        }

        let result: Result<LoopbackPrimaryTLSTestFixture.Material, LiveRuntimeTestHarnessError>
        do {
            result = .success(try LoopbackPrimaryTLSTestFixture.makeMaterial())
        } catch let error as LiveRuntimeTestHarnessError {
            result = .failure(error)
        } catch {
            result = .failure(
                .invalidTLSFixture("TLS loopback material generation failed: \(error)")
            )
        }

        materialResult = result
        switch result {
        case let .success(material):
            return material
        case let .failure(error):
            throw error
        }
    }
}
