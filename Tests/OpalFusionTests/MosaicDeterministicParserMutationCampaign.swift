// MosaicDeterministicParserMutationCampaign.swift

import Testing

struct MosaicDeterministicParserMutationVector {
    let name: String
    let seedBytes: [UInt8]
    let validateAcceptedBytes: ([UInt8]) throws -> Bool
}

enum MosaicDeterministicParserMutationCampaign {
    private struct Mutation {
        let name: String
        let bytes: [UInt8]
    }

    static func validate(
        _ vectors: [MosaicDeterministicParserMutationVector],
        seed: UInt64,
        seededMutationCount: Int
    ) throws {
        try #require(vectors.isEmpty == false)
        try #require(seededMutationCount > 0)

        for (vectorIndex, vector) in vectors.enumerated() {
            let vectorSeed = seed &+ UInt64(vectorIndex)
            let seedText = String(vectorSeed, radix: 16)
            try #require(vector.seedBytes.isEmpty == false)
            #expect(
                try vector.validateAcceptedBytes(vector.seedBytes),
                "Positive parser seed is unstable: \(vector.name), seed=\(seedText)"
            )

            let mutations = mutations(
                of: vector.seedBytes,
                seed: vectorSeed,
                seededMutationCount: seededMutationCount
            )
            var rejectedCount = 0

            for mutation in mutations
            where mutation.bytes != vector.seedBytes {
                do {
                    let stable = try vector.validateAcceptedBytes(
                        mutation.bytes
                    )
                    #expect(
                        stable,
                        "Accepted bytes were not stable: \(vector.name), seed=\(seedText), mutation=\(mutation.name)"
                    )
                } catch {
                    rejectedCount += 1
                }
            }

            #expect(
                rejectedCount > 0,
                "Mutation campaign did not exercise rejection: \(vector.name), seed=\(seedText)"
            )
        }
    }

    private static func mutations(
        of original: [UInt8],
        seed: UInt64,
        seededMutationCount: Int
    ) -> [Mutation] {
        var result: [Mutation] = []
        let lastIndex = original.count - 1
        let boundaryOffsets = Array(
            Set([0, 1, original.count / 4, original.count / 2,
                 original.count * 3 / 4, lastIndex])
        )
        .filter { original.indices.contains($0) }
        .sorted()

        for count in boundaryOffsets {
            result.append(
                .init(
                    name: "truncate-\(count)",
                    bytes: Array(original.prefix(count))
                )
            )
        }
        for byte in [UInt8(0), UInt8.max] {
            result.append(
                .init(
                    name: "prefix-\(byte)",
                    bytes: [byte] + original
                )
            )
            result.append(
                .init(
                    name: "suffix-\(byte)",
                    bytes: original + [byte]
                )
            )
        }
        for index in boundaryOffsets {
            var deleted = original
            deleted.remove(at: index)
            result.append(
                .init(name: "delete-\(index)", bytes: deleted)
            )

            for replacement in [UInt8(0), UInt8(1), UInt8(0x7F),
                                UInt8(0x80), UInt8.max] {
                var replaced = original
                replaced[index] = replacement
                result.append(
                    .init(
                        name: "replace-\(index)-\(replacement)",
                        bytes: replaced
                    )
                )
            }
        }

        var state = seed
        for iteration in 0 ..< seededMutationCount {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let index = Int(state % UInt64(original.count))
            let replacement = UInt8(truncatingIfNeeded: state >> 40)
            var mutation = original
            mutation[index] ^= replacement | 1
            result.append(
                .init(
                    name: "seeded-\(iteration)-\(index)",
                    bytes: mutation
                )
            )
        }

        return result
    }
}
