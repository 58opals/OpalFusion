// OpalFusion+Round+Identifier.swift

public extension OpalFusion.Round {
    struct Identifier: Sendable, Equatable, Hashable, RawRepresentable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}
