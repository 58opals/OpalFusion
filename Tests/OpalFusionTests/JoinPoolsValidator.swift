// JoinPoolsValidator.swift

@testable import OpalFusion
import Testing

struct JoinPoolsValidator {
    @Test("Join pools preserves requested tiers and multiple pool tags")
    func validateJoinPoolsConstruction() {
        let firstTag = OpalFusion.ProtocolModel.PoolTag(
            identifier: [0x01, 0x02],
            limit: 2,
            noIp: true
        )
        let secondTag = OpalFusion.ProtocolModel.PoolTag(
            identifier: [0x03, 0x04],
            limit: 5
        )
        let joinPools = OpalFusion.ProtocolModel.JoinPools(
            tiers: [100_000, 250_000],
            tags: [firstTag, secondTag]
        )

        #expect(joinPools.tiers == [100_000, 250_000])
        #expect(joinPools.tags == [firstTag, secondTag])
        #expect(joinPools.tags[0].noIp == true)
        #expect(joinPools.tags[1].noIp == nil)
    }

    @Test("Join pool tags accept official boundary values")
    func validatePoolTagBoundaryValues() {
        let tags = [
            OpalFusion.ProtocolModel.PoolTag(identifier: [0x01], limit: 5, noIp: true),
            OpalFusion.ProtocolModel.PoolTag(identifier: [0x02], limit: 5),
            OpalFusion.ProtocolModel.PoolTag(identifier: [0x03], limit: 5),
            OpalFusion.ProtocolModel.PoolTag(identifier: [0x04], limit: 5),
            OpalFusion.ProtocolModel.PoolTag(
                identifier: [UInt8](repeating: 0x05, count: 20),
                limit: 5
            )
        ]
        let joinPools = OpalFusion.ProtocolModel.JoinPools(
            tiers: [10_000],
            tags: tags
        )

        #expect(
            OpalFusion.Runtime.validateStartupConfiguration(
                PrimaryRuntimeTestFixtures.configuration,
                genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
                joinPools: joinPools
            ) == nil
        )
        #expect(joinPools.tags.count == 5)
        #expect(joinPools.tags[4].identifier.count == 20)
        #expect(joinPools.tags.allSatisfy { $0.limit == 5 })
    }

    @Test("Join pool tags reject official boundary violations")
    func validatePoolTagBoundaryViolations() {
        #expect(
            Self.startupValidationSummary(
                tags: (0 ..< 6).map { index in
                    .init(identifier: [UInt8(index + 1)], limit: 1)
                }
            ) == "Join pool tags must not exceed five entries"
        )
        #expect(
            Self.startupValidationSummary(
                tags: [.init(identifier: [UInt8](repeating: 0x01, count: 21), limit: 1)]
            ) == "Join pool tag identifiers must not exceed 20 bytes"
        )
        #expect(
            Self.startupValidationSummary(
                tags: [.init(identifier: [0x01], limit: 6)]
            ) == "Join pool tag limits must not exceed five"
        )
    }

    private static func startupValidationSummary(
        tags: [OpalFusion.ProtocolModel.PoolTag]
    ) -> String? {
        OpalFusion.Runtime.validateStartupConfiguration(
            PrimaryRuntimeTestFixtures.configuration,
            genesisHash: PrimaryRuntimeTestFixtures.clientHello.genesisHash,
            joinPools: .init(
                tiers: [10_000],
                tags: tags
            )
        )
    }
}
