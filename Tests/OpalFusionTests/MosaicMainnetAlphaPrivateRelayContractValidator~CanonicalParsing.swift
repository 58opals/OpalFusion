// MosaicMainnetAlphaPrivateRelayContractValidator~CanonicalParsing.swift

import Testing
@testable import OpalFusion

extension MosaicMainnetAlphaPrivateRelayContractValidator {
    @Test("Fuzz relay endpoint parsing with a deterministic bound")
    func fuzzRelayEndpointParsingWithDeterministicBound() throws {
        var state: UInt64 = 0x6A09_E667_F3BC_C909
        for _ in 0 ..< 256 {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let length = Int(state % 48)
            var bytes: [UInt8] = []
            for _ in 0 ..< length {
                state = state &* 2_862_933_555_777_941_757 &+ 3_037_000_493
                bytes.append(UInt8(truncatingIfNeeded: state >> 24))
            }
            let candidate = String(decoding: bytes, as: UTF8.self)
            if let endpoint = try? Alpha.PrivateRelayEndpoint(
                normalizing: candidate
            ) {
                #expect(endpoint.normalizedURL.hasPrefix("wss://"))
                #expect(endpoint.normalizedURL.hasSuffix("/"))
                #expect(
                    try Alpha.PrivateRelayEndpoint(
                        normalizing: endpoint.normalizedURL
                    ) == endpoint
                )
            }
        }
    }

    func makeRelaySet() throws -> Alpha.RelaySetDocument {
        try .init(
            registrations: try (1 ... 3).map {
                try makeRegistration(index: $0)
            }
        )
    }

    func makeRegistration(
        index: Int
    ) throws -> Alpha.RelayRegistrationDocument {
        try .init(
            endpoint: Alpha.PrivateRelayEndpoint(
                normalizing: "wss://relay-\(index == 1 ? "a" : index == 2 ? "b" : "c").example/"
            ),
            operatorIdentity: Alpha.RelayOperatorIdentity(
                appReviewedRegistryLabel: "operator \(index)"
            ),
            requiresNIP42Authentication: false,
            requiresProofOfWork: false
        )
    }
}
