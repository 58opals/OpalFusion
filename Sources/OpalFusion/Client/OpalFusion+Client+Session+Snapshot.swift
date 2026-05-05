// OpalFusion+Client+Session+Snapshot.swift

public extension OpalFusion.Client.Session {
    struct Snapshot: Sendable, Equatable {
        public let state: OpalFusion.Client.State
        public let lastError: OpalFusion.Client.Error?
        public let lastErrorSummary: String?
        public let diagnostics: OpalFusion.Client.Diagnostics

        public init(
            state: OpalFusion.Client.State = .init(),
            lastError: OpalFusion.Client.Error? = nil,
            lastErrorSummary: String? = nil,
            diagnostics: OpalFusion.Client.Diagnostics = .init()
        ) {
            self.state = state
            self.lastError = lastError
            self.lastErrorSummary = lastErrorSummary
            self.diagnostics = diagnostics
        }
    }
}
