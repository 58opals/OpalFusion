// OpalFusion+Transport+BaselineConfiguration.swift

public extension OpalFusion.Transport {
    /// A pinned public interoperability profile for CashFusion transport framing and timing values.
    struct BaselineConfiguration: Sendable, Equatable {
        /// Primary-channel framing values for the baseline.
        public let framing: OpalFusion.Transport.FrameConfiguration
        /// Covert connection timing values for the baseline.
        public let covertTiming: OpalFusion.Transport.CovertTimingConfiguration
        /// Round lifecycle timing values for the baseline.
        public let roundTiming: OpalFusion.Transport.RoundTimingConfiguration

        public init(
            framing: OpalFusion.Transport.FrameConfiguration,
            covertTiming: OpalFusion.Transport.CovertTimingConfiguration,
            roundTiming: OpalFusion.Transport.RoundTimingConfiguration
        ) {
            self.framing = framing
            self.covertTiming = covertTiming
            self.roundTiming = roundTiming
        }

        /// Electron Cash 4.4.3 framing and timing values from `connection.py` and `protocol.py`.
        public static let electronCash443 = Self(
            framing: .init(
                magicBytes: [0x76, 0x5b, 0xe8, 0xb4, 0xe4, 0x39, 0x6d, 0xcf],
                maximumMessageLengthBytes: 200 * 1024
            ),
            covertTiming: .init(
                connectTimeout: .seconds(15),
                connectWindow: .seconds(15),
                submitTimeout: .seconds(3),
                submitWindow: .seconds(5),
                spareConnectionCount: 6
            ),
            roundTiming: .init(
                maximumClockDiscrepancy: .seconds(5),
                warmupDuration: .seconds(30),
                warmupSlop: .seconds(3),
                commitmentsDeadlineFromRoundStart: .seconds(3),
                covertComponentsStartFromRoundStart: .seconds(5),
                covertComponentsDeadlineFromRoundStart: .seconds(15),
                signaturesStartFromRoundStart: .seconds(20),
                signaturesDeadlineFromRoundStart: .seconds(30),
                conclusionTimeoutFromRoundStart: .seconds(35),
                closeStartFromRoundStart: .seconds(45),
                blameCloseStartFromRoundStart: .seconds(80),
                standardTimeout: .seconds(3),
                blameVerifyDuration: .seconds(5)
            )
        )
    }
}
