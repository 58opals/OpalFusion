// OpalFusion+Transport+CovertTimingConfiguration.swift

public extension OpalFusion.Transport {
    /// Covert connection timing values for the pinned Electron Cash interoperability baseline.
    struct CovertTimingConfiguration: Sendable, Equatable {
        /// Electron Cash `COVERT_CONNECT_TIMEOUT`.
        public let connectTimeout: Duration
        /// Electron Cash `COVERT_CONNECT_WINDOW`.
        public let connectWindow: Duration
        /// Electron Cash `COVERT_SUBMIT_TIMEOUT`.
        public let submitTimeout: Duration
        /// Electron Cash `COVERT_SUBMIT_WINDOW`.
        public let submitWindow: Duration
        /// Electron Cash `COVERT_CONNECT_SPARES`.
        public let spareConnectionCount: Int

        public init(
            connectTimeout: Duration,
            connectWindow: Duration,
            submitTimeout: Duration,
            submitWindow: Duration,
            spareConnectionCount: Int
        ) {
            self.connectTimeout = connectTimeout
            self.connectWindow = connectWindow
            self.submitTimeout = submitTimeout
            self.submitWindow = submitWindow
            self.spareConnectionCount = spareConnectionCount
        }
    }
}
