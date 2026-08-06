// OpalFusion+Host+MosaicReservationRequest.swift

import Foundation

public extension OpalFusion.Host {
    /// The manifest-bound requirements supplied when one Mosaic contributor becomes reservation-eligible.
    struct MosaicReservationRequest: Sendable, Equatable {
        public let attemptIdentifier: [UInt8]
        public let networkGenesisHash: [UInt8]
        public let roundIdentifier: [UInt8]
        public let expiresAt: Date
        public let componentCount: Int
        public let feeRateSatoshisPerByte: UInt64
        public let minimumExcessFeeSatoshis: UInt64
        public let maximumExcessFeeSatoshis: UInt64
        public let transactionProfileIdentifier: String

        public init(
            attemptIdentifier: [UInt8],
            networkGenesisHash: [UInt8],
            roundIdentifier: [UInt8],
            expiresAt: Date,
            componentCount: Int,
            feeRateSatoshisPerByte: UInt64,
            minimumExcessFeeSatoshis: UInt64,
            maximumExcessFeeSatoshis: UInt64,
            transactionProfileIdentifier: String
        ) throws {
            guard !attemptIdentifier.isEmpty else {
                throw MosaicHostContractError.emptyAttemptIdentifier
            }
            guard networkGenesisHash.count == 32 else {
                throw MosaicHostContractError.invalidNetworkGenesisHashLength(
                    actual: networkGenesisHash.count
                )
            }
            guard roundIdentifier.count == 32 else {
                throw MosaicHostContractError.invalidRoundIdentifierLength(
                    actual: roundIdentifier.count
                )
            }
            guard componentCount > 0 else {
                throw MosaicHostContractError.invalidComponentCount(actual: componentCount)
            }
            guard minimumExcessFeeSatoshis <= maximumExcessFeeSatoshis else {
                throw MosaicHostContractError.invalidExcessFeeRange(
                    minimum: minimumExcessFeeSatoshis,
                    maximum: maximumExcessFeeSatoshis
                )
            }
            guard !transactionProfileIdentifier.isEmpty else {
                throw MosaicHostContractError.emptyTransactionProfileIdentifier
            }
            guard transactionProfileIdentifier.unicodeScalars.allSatisfy({
                (0x20 ... 0x7e).contains($0.value)
            }) else {
                throw MosaicHostContractError.nonASCIITransactionProfileIdentifier
            }

            self.attemptIdentifier = Array(attemptIdentifier)
            self.networkGenesisHash = Array(networkGenesisHash)
            self.roundIdentifier = Array(roundIdentifier)
            self.expiresAt = expiresAt
            self.componentCount = componentCount
            self.feeRateSatoshisPerByte = feeRateSatoshisPerByte
            self.minimumExcessFeeSatoshis = minimumExcessFeeSatoshis
            self.maximumExcessFeeSatoshis = maximumExcessFeeSatoshis
            self.transactionProfileIdentifier = transactionProfileIdentifier
        }
    }
}
