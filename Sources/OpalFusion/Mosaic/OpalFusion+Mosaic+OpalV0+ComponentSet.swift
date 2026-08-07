// OpalFusion+Mosaic+OpalV0+ComponentSet.swift

import Foundation

extension OpalFusion.Mosaic.OpalV0 {
    struct ComponentSet: Sendable, Equatable {
        private struct Outpoint: Hashable {
            let transactionHash: [UInt8]
            let outputIndex: UInt32
        }

        let components: [Component]
        let canonicalBytes: [UInt8]
        let digest: [UInt8]

        init(components: [Component]) throws {
            guard OpalFusion.Mosaic.OpalV0.isValidAggregateMemberCount(
                components.count
            ) else {
                throw WireContractError.invalidComponentSetCount(
                    actual: components.count
                )
            }

            let encodedMembers = try components.map {
                (
                    value: $0,
                    bytes: try CanonicalWireCodec.encodeComponent($0)
                )
            }.sorted { lhs, rhs in
                lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
            }
            for index in encodedMembers.indices.dropFirst() {
                guard encodedMembers[index - 1].bytes != encodedMembers[index].bytes else {
                    throw WireContractError.duplicateComponentSetMember
                }
            }

            var saltCommitments = Set<Data>()
            for component in components {
                guard saltCommitments.insert(
                    Data(component.saltCommitment)
                ).inserted else {
                    throw WireContractError.duplicateSaltCommitment
                }
            }

            var inputOutpoints = Set<Outpoint>()
            for component in components {
                guard case let .input(input) = component.payload else {
                    continue
                }
                guard inputOutpoints.insert(
                    .init(
                        transactionHash: input.previousTransactionHash,
                        outputIndex: input.outputIndex
                    )
                ).inserted else {
                    throw WireContractError.duplicateInputOutpoint
                }
            }

            let sortedComponents = encodedMembers.map(\.value)
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            try encoder.writeSortedSet(sortedComponents) { encoder, component in
                try CanonicalWireCodec.writeComponent(component, to: &encoder)
            }
            let canonicalBytes = encoder.encodedBytes

            self.components = sortedComponents
            self.canonicalBytes = canonicalBytes
            self.digest = OpalFusion.Mosaic.OpalV0.aggregateDigest(
                domainSuffix: "component-set",
                canonicalBytes: canonicalBytes
            )
        }
    }
}
