// OpalFusion+Host+ParticipantReservationContext.swift

public extension OpalFusion.Host {
    struct ParticipantReservationContext: Sendable, Equatable {
        public let roundIdentifier: OpalFusion.Round.Identifier
        public let tierSatoshis: UInt64
        public let numberOfComponents: UInt32
        public let componentFeeRateSatoshisPerKb: UInt64
        public let minimumExcessFeeSatoshis: UInt64
        public let maximumExcessFeeSatoshis: UInt64

        public init(
            roundIdentifier: OpalFusion.Round.Identifier,
            tierSatoshis: UInt64,
            numberOfComponents: UInt32,
            componentFeeRateSatoshisPerKb: UInt64,
            minimumExcessFeeSatoshis: UInt64,
            maximumExcessFeeSatoshis: UInt64
        ) {
            self.roundIdentifier = roundIdentifier
            self.tierSatoshis = tierSatoshis
            self.numberOfComponents = numberOfComponents
            self.componentFeeRateSatoshisPerKb = componentFeeRateSatoshisPerKb
            self.minimumExcessFeeSatoshis = minimumExcessFeeSatoshis
            self.maximumExcessFeeSatoshis = maximumExcessFeeSatoshis
        }
    }
}
