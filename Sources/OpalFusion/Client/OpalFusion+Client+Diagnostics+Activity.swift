// OpalFusion+Client+Diagnostics+Activity.swift

public extension OpalFusion.Client.Diagnostics {
    enum Activity: String, Sendable, Equatable {
        case idle
        case connecting
        case running
        case retrying
        case failed
        case stopped
    }
}
