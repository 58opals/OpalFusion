// OpalFusion+Transport+BaselineConfiguration.swift

public extension OpalFusion.Transport {
    /// A pinned public interoperability profile for CashFusion transport identity, framing, and timing values.
    struct BaselineConfiguration: Sendable, Equatable {
        /// Protocol identity values for the baseline.
        public let protocolIdentity: OpalFusion.Transport.ProtocolIdentityConfiguration
        /// Primary-channel framing values for the baseline.
        public let framing: OpalFusion.Transport.FrameConfiguration
        /// Covert connection timing values for the baseline.
        public let covertTiming: OpalFusion.Transport.CovertTimingConfiguration
        /// Round lifecycle timing values for the baseline.
        public let roundTiming: OpalFusion.Transport.RoundTimingConfiguration

        public init(
            protocolIdentity: OpalFusion.Transport.ProtocolIdentityConfiguration,
            framing: OpalFusion.Transport.FrameConfiguration,
            covertTiming: OpalFusion.Transport.CovertTimingConfiguration,
            roundTiming: OpalFusion.Transport.RoundTimingConfiguration
        ) {
            self.protocolIdentity = protocolIdentity
            self.framing = framing
            self.covertTiming = covertTiming
            self.roundTiming = roundTiming
        }

        public init(
            framing: OpalFusion.Transport.FrameConfiguration,
            covertTiming: OpalFusion.Transport.CovertTimingConfiguration,
            roundTiming: OpalFusion.Transport.RoundTimingConfiguration
        ) {
            self.init(
                protocolIdentity: Self.electronCash443.protocolIdentity,
                framing: framing,
                covertTiming: covertTiming,
                roundTiming: roundTiming
            )
        }

        /// Electron Cash 4.4.3 framing and timing values from `connection.py` and `protocol.py`.
        public static let electronCash443 = Self(
            protocolIdentity: .init(
                versionBytes: [0x61, 0x6C, 0x70, 0x68, 0x61, 0x31, 0x33],
                fusionLokadId: [0x46, 0x55, 0x5A, 0x00],
                minimumOutputAmountSatoshis: 10_000
            ),
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
