// OpalFusion+Host+MosaicReservationReference.swift

import Foundation

public extension OpalFusion.Host {
    /// An opaque host-owned reservation identity paired with its current generation.
    ///
    /// The generation prevents a delayed callback from acting on a replacement lease.
    struct MosaicReservationReference: Sendable, Hashable {
        public let identifier: UUID
        public let generation: UInt64

        public init(identifier: UUID, generation: UInt64) {
            self.identifier = identifier
            self.generation = generation
        }
    }
}
