// OpalFusion+MosaicPrivateAlphaRuntime+Binding.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Immutable Fusion attempt, generation, and material identity.
    ///
    /// `generationIdentifier` is Fusion's 32-byte generation guard. It is deliberately distinct
    /// from the wallet reservation reference's `UInt64` generation.
    @_spi(MosaicPrivateAlpha)
    public struct Binding: Hashable, Sendable {
        @_spi(MosaicPrivateAlpha) public let attemptIdentifier: Data
        @_spi(MosaicPrivateAlpha) public let generationIdentifier: Data
        @_spi(MosaicPrivateAlpha) public let materialIdentifier: Data

        @_spi(MosaicPrivateAlpha)
        public init(
            attemptIdentifier: Data,
            generationIdentifier: Data,
            materialIdentifier: Data
        ) throws {
            for identifier in [
                attemptIdentifier,
                generationIdentifier,
                materialIdentifier,
            ] {
                guard identifier.count == 32 else {
                    throw Failure.invalidIdentifierByteCount(
                        expected: 32,
                        actual: identifier.count
                    )
                }
            }
            self.attemptIdentifier = attemptIdentifier
            self.generationIdentifier = generationIdentifier
            self.materialIdentifier = materialIdentifier
        }
    }
}
#endif
