// JoinPoolsValidator.swift

import OpalFusion
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
}
