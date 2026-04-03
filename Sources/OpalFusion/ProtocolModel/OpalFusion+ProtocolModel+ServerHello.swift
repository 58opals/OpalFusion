// OpalFusion+ProtocolModel+ServerHello.swift

public extension OpalFusion.ProtocolModel {
    /// Server-advertised pool and fee configuration for a connection.
    struct ServerHello: Sendable, Equatable {
        /// `fusion.proto` `ServerHello.tiers`.
        public let tiers: [UInt64]
        /// `fusion.proto` `ServerHello.num_components`.
        public let numberOfComponents: UInt32
        /// `fusion.proto` `ServerHello.component_feerate`.
        public let componentFeeRateSatoshisPerKb: UInt64
        /// `fusion.proto` `ServerHello.min_excess_fee`.
        public let minimumExcessFeeSatoshis: UInt64
        /// `fusion.proto` `ServerHello.max_excess_fee`.
        public let maximumExcessFeeSatoshis: UInt64
        /// `fusion.proto` `ServerHello.donation_address`.
        public let donationAddress: String?

        public init(
            tiers: [UInt64],
            numberOfComponents: UInt32,
            componentFeeRateSatoshisPerKb: UInt64,
            minimumExcessFeeSatoshis: UInt64,
            maximumExcessFeeSatoshis: UInt64,
            donationAddress: String? = nil
        ) {
            self.tiers = tiers
            self.numberOfComponents = numberOfComponents
            self.componentFeeRateSatoshisPerKb = componentFeeRateSatoshisPerKb
            self.minimumExcessFeeSatoshis = minimumExcessFeeSatoshis
            self.maximumExcessFeeSatoshis = maximumExcessFeeSatoshis
            self.donationAddress = donationAddress
        }
    }
}
