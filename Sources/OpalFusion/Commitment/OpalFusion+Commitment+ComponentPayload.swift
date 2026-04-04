// OpalFusion+Commitment+ComponentPayload.swift

public extension OpalFusion.Commitment {
    /// The concrete payload carried by one commitment component.
    enum ComponentPayload: Sendable, Equatable {
        case input(OpalFusion.Commitment.InputComponent)
        case output(OpalFusion.Commitment.OutputComponent)
        case blank(OpalFusion.Commitment.BlankComponent)
    }
}
