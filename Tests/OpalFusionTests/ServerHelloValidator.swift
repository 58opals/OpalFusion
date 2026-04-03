// ServerHelloValidator.swift

import OpalFusion
import Testing

struct ServerHelloValidator {
    @Test("Server hello preserves tier, fee, and donation fields")
    func validateServerHelloConstruction() {
        let hello = OpalFusion.ProtocolModel.ServerHello(
            tiers: [100_000, 1_000_000],
            numberOfComponents: 37,
            componentFeeRateSatoshisPerKb: 2_000,
            minimumExcessFeeSatoshis: 120,
            maximumExcessFeeSatoshis: 800,
            donationAddress: "bitcoincash:qz0l0example"
        )

        #expect(hello.tiers == [100_000, 1_000_000])
        #expect(hello.numberOfComponents == 37)
        #expect(hello.componentFeeRateSatoshisPerKb == 2_000)
        #expect(hello.minimumExcessFeeSatoshis == 120)
        #expect(hello.maximumExcessFeeSatoshis == 800)
        #expect(hello.donationAddress == "bitcoincash:qz0l0example")
    }
}
