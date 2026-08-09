// OpalFusion+Mosaic+OpalMainnetAlpha+ContributionFeePolicy.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// The alpha.3 allocation of BCH's fixed transaction bytes across contributors.
    enum ContributionFeePolicy {
        enum ValidationError: Error, Sendable, Equatable {
            case conductorCannotContribute
            case unknownContributor
            case invalidComponentCounts(inputs: Int, outputs: Int)
        }

        static let standardInputByteCount = 141
        static let standardOutputByteCount = 34

        /// Returns this contributor's exact share of the fixed ten-byte transaction overhead.
        ///
        /// Contributors are ordered lexicographically by their one-time control identities.
        /// Integer division supplies the base share and the first remainder members pay one
        /// additional satoshi, so the 6–8 shares always total exactly ten satoshis.
        static func requiredExcessFeeSatoshis(
            for contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            in roster: OpalFusion.Mosaic.Attempt.Roster
        ) throws -> UInt64 {
            guard contributor != roster.conductor else {
                throw ValidationError.conductorCannotContribute
            }
            let orderedContributors = roster.contributors.sorted {
                $0.validatedBytes.lexicographicallyPrecedes($1.validatedBytes)
            }
            guard let index = orderedContributors.firstIndex(of: contributor) else {
                throw ValidationError.unknownContributor
            }
            let baseShare = fixedTransactionOverheadByteCount
                / orderedContributors.count
            let additionalShareCount = fixedTransactionOverheadByteCount
                % orderedContributors.count
            return UInt64(baseShare + (index < additionalShareCount ? 1 : 0))
        }

        static func expectedFinalFeeSatoshis(
            inputCount: Int,
            outputCount: Int
        ) throws -> UInt64 {
            guard inputCount > 0,
                  outputCount > 0,
                  inputCount < maximumTransactionComponentCount,
                  outputCount < maximumTransactionComponentCount,
                  inputCount + outputCount <= maximumTransactionComponentCount else {
                throw ValidationError.invalidComponentCounts(
                    inputs: inputCount,
                    outputs: outputCount
                )
            }
            return UInt64(
                fixedTransactionOverheadByteCount
                    + inputCount * standardInputByteCount
                    + outputCount * standardOutputByteCount
            ) * feeRateSatoshisPerByte
        }

        static func contributionSatoshis(
            for component: OpalFusion.Mosaic.OpalV0.ComponentPayload
        ) -> Int64 {
            switch component {
            case let .input(input):
                Int64(input.amountSatoshis)
                    - Int64(standardInputByteCount)
            case let .output(output):
                -(Int64(output.amountSatoshis)
                    + Int64(standardOutputByteCount))
            case .blank:
                0
            }
        }
    }
}
