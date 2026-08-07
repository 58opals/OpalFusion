// OpalFusion+Mosaic+OpalV0+SequenceTracker.swift

extension OpalFusion.Mosaic.OpalV0 {
    struct SequenceTracker: Sendable {
        enum Failure: Error, Sendable, Equatable {
            case sequenceGap(expected: UInt64, received: UInt64)
            case sequenceConflict(sequence: UInt64)
            case inputAfterTermination
        }

        enum Decision: Sendable, Equatable {
            case accepted
            case exactDuplicate
            case terminated(Failure)
            case rejected(Failure)
        }

        private var identifiersBySequence: [UInt64: [UInt8]] = [:]
        private var nextSequence: UInt64 = 0
        private var terminalFailure: Failure?

        mutating func record(sequence: UInt64, messageIdentifier: [UInt8]) -> Decision {
            if terminalFailure != nil {
                return .rejected(.inputAfterTermination)
            }
            if let existingIdentifier = identifiersBySequence[sequence] {
                if existingIdentifier == messageIdentifier {
                    return .exactDuplicate
                }
                return terminate(with: .sequenceConflict(sequence: sequence))
            }
            guard sequence == nextSequence else {
                return terminate(
                    with: .sequenceGap(expected: nextSequence, received: sequence)
                )
            }

            identifiersBySequence[sequence] = Array(messageIdentifier)
            nextSequence += 1
            return .accepted
        }

        private mutating func terminate(with failure: Failure) -> Decision {
            terminalFailure = failure
            return .terminated(failure)
        }
    }
}
