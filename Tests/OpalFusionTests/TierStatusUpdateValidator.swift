// TierStatusUpdateValidator.swift

import OpalFusion
import Testing

struct TierStatusUpdateValidator {
    @Test("Tier status update preserves sparse tier metadata by tier identifier")
    func validateTierStatusUpdateConstruction() {
        let lowTierStatus = OpalFusion.ProtocolModel.TierStatus(
            playerCount: 5,
            minimumPlayerCount: 4
        )
        let highTierStatus = OpalFusion.ProtocolModel.TierStatus(
            maximumPlayerCount: 10,
            timeRemainingSeconds: 42
        )
        let update = OpalFusion.ProtocolModel.TierStatusUpdate(
            statusesByTier: [
                100_000: lowTierStatus,
                1_000_000: highTierStatus
            ]
        )

        #expect(update.statusesByTier[100_000] == lowTierStatus)
        #expect(update.statusesByTier[1_000_000] == highTierStatus)
        #expect(update.statusesByTier[100_000]?.maximumPlayerCount == nil)
        #expect(update.statusesByTier[1_000_000]?.timeRemainingSeconds == 42)
    }
}
