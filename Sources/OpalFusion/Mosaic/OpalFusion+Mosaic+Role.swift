// OpalFusion+Mosaic+Role.swift

public extension OpalFusion.Mosaic {
    /// A role held for one Mosaic attempt.
    enum Role: CaseIterable, Sendable, Hashable {
        /// The non-contributing peer that conducts one attempt.
        case conductor
        /// A peer that contributes wallet inputs and fresh outputs.
        case contributor
    }
}
