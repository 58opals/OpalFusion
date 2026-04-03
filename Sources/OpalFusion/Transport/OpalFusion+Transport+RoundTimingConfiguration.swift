// OpalFusion+Transport+RoundTimingConfiguration.swift

public extension OpalFusion.Transport {
    /// Round lifecycle timing values for the pinned Electron Cash interoperability baseline.
    struct RoundTimingConfiguration: Sendable, Equatable {
        /// Electron Cash `MAX_CLOCK_DISCREPANCY`.
        public let maximumClockDiscrepancy: Duration
        /// Electron Cash `WARMUP_TIME`.
        public let warmupDuration: Duration
        /// Electron Cash `WARMUP_SLOP`.
        public let warmupSlop: Duration
        /// Electron Cash `TS_EXPECTING_COMMITMENTS`.
        public let commitmentsDeadlineFromRoundStart: Duration
        /// Electron Cash `T_START_COMPS`.
        public let covertComponentsStartFromRoundStart: Duration
        /// Electron Cash `TS_EXPECTING_COVERT_COMPONENTS`.
        public let covertComponentsDeadlineFromRoundStart: Duration
        /// Electron Cash `T_START_SIGS`.
        public let signaturesStartFromRoundStart: Duration
        /// Electron Cash `TS_EXPECTING_COVERT_SIGNATURES`.
        public let signaturesDeadlineFromRoundStart: Duration
        /// Electron Cash `T_EXPECTING_CONCLUSION`.
        public let conclusionTimeoutFromRoundStart: Duration
        /// Electron Cash `T_START_CLOSE`.
        public let closeStartFromRoundStart: Duration
        /// Electron Cash `T_START_CLOSE_BLAME`.
        public let blameCloseStartFromRoundStart: Duration
        /// Electron Cash `STANDARD_TIMEOUT`.
        public let standardTimeout: Duration
        /// Electron Cash `BLAME_VERIFY_TIME`.
        public let blameVerifyDuration: Duration

        public init(
            maximumClockDiscrepancy: Duration,
            warmupDuration: Duration,
            warmupSlop: Duration,
            commitmentsDeadlineFromRoundStart: Duration,
            covertComponentsStartFromRoundStart: Duration,
            covertComponentsDeadlineFromRoundStart: Duration,
            signaturesStartFromRoundStart: Duration,
            signaturesDeadlineFromRoundStart: Duration,
            conclusionTimeoutFromRoundStart: Duration,
            closeStartFromRoundStart: Duration,
            blameCloseStartFromRoundStart: Duration,
            standardTimeout: Duration,
            blameVerifyDuration: Duration
        ) {
            self.maximumClockDiscrepancy = maximumClockDiscrepancy
            self.warmupDuration = warmupDuration
            self.warmupSlop = warmupSlop
            self.commitmentsDeadlineFromRoundStart = commitmentsDeadlineFromRoundStart
            self.covertComponentsStartFromRoundStart = covertComponentsStartFromRoundStart
            self.covertComponentsDeadlineFromRoundStart = covertComponentsDeadlineFromRoundStart
            self.signaturesStartFromRoundStart = signaturesStartFromRoundStart
            self.signaturesDeadlineFromRoundStart = signaturesDeadlineFromRoundStart
            self.conclusionTimeoutFromRoundStart = conclusionTimeoutFromRoundStart
            self.closeStartFromRoundStart = closeStartFromRoundStart
            self.blameCloseStartFromRoundStart = blameCloseStartFromRoundStart
            self.standardTimeout = standardTimeout
            self.blameVerifyDuration = blameVerifyDuration
        }
    }
}
