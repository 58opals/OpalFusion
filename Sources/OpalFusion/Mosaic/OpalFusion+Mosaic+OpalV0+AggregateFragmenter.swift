// OpalFusion+Mosaic+OpalV0+AggregateFragmenter.swift

extension OpalFusion.Mosaic.OpalV0 {
    enum AggregateFragmenter: Sendable {
        static func fragments(
            for commitmentSet: CommitmentSet,
            roundIdentifier: [UInt8]
        ) throws -> [AggregateFragment] {
            try fragments(
                aggregateKind: .commitmentSet,
                aggregateDigest: commitmentSet.digest,
                canonicalBytes: commitmentSet.canonicalBytes,
                roundIdentifier: roundIdentifier
            )
        }

        static func fragments(
            for componentSet: ComponentSet,
            roundIdentifier: [UInt8]
        ) throws -> [AggregateFragment] {
            try fragments(
                aggregateKind: .componentSet,
                aggregateDigest: componentSet.digest,
                canonicalBytes: componentSet.canonicalBytes,
                roundIdentifier: roundIdentifier
            )
        }

        private static func fragments(
            aggregateKind: AggregateFragment.Kind,
            aggregateDigest: [UInt8],
            canonicalBytes: [UInt8],
            roundIdentifier: [UInt8]
        ) throws -> [AggregateFragment] {
            let descriptor = try AggregateFragment.Descriptor(
                roundIdentifier: roundIdentifier,
                aggregateKind: aggregateKind,
                aggregateDigest: aggregateDigest,
                declaredAggregateByteCount: canonicalBytes.count
            )
            let bodyCapacity = OpalFusion.Mosaic.OpalV0
                .maximumAggregateFragmentBodyByteCount
            return try (0 ..< descriptor.fragmentCount).map { fragmentIndex in
                let lowerBound = fragmentIndex * bodyCapacity
                let upperBound = min(
                    lowerBound + bodyCapacity,
                    canonicalBytes.count
                )
                return try .init(
                    descriptor: descriptor,
                    fragmentIndex: fragmentIndex,
                    body: Array(canonicalBytes[lowerBound ..< upperBound])
                )
            }
        }
    }
}
