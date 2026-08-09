// OpalFusion+Mosaic+OpalV0+AuthorizationIssuanceLedger.swift

import OpalCrypto

extension OpalFusion.Mosaic.OpalV0 {
    /// A deterministic one-attempt ledger for component-authorization issuance.
    struct AuthorizationIssuanceLedger: Sendable {
        enum Phase: Sendable, Equatable {
            case collecting
            case evaluating
            case issued
            case failed(Failure)
        }

        enum Failure: Error, Sendable, Equatable {
            case conductorSubmittedAuthorization
            case unknownContributor
            case invalidSlot(actual: Int)
            case conflictingSlotReuse(RequestKey)
            case unexpectedEvaluationResult(RequestKey)
            case conflictingEvaluationResult(RequestKey)
            case evaluationFailed(RequestKey)
            case inputAfterTermination
        }

        enum IssuedResponseError: Error, Sendable, Equatable {
            case issuanceIncomplete
            case unknownContributor
            case requestCountMismatch(actual: Int)
            case requestMismatch(slot: Int)
        }

        struct RequestKey: Sendable, Hashable {
            let contributor: OpalFusion.Mosaic.Attempt.ControlIdentity
            let slot: Int
        }

        struct Evaluation: Sendable, Equatable {
            let key: RequestKey
            let blindedMessage: OpalCrypto.RSABSSA.BlindedMessage
        }

        struct Response: Sendable, Equatable {
            let key: RequestKey
            let blindSignature: OpalCrypto.RSABSSA.BlindSignature
        }

        enum Input: Sendable, Equatable {
            case request(
                contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
                slot: Int,
                blindedMessage: OpalCrypto.RSABSSA.BlindedMessage
            )
            case evaluated(Response)
            case evaluationFailed(RequestKey)
        }

        enum Effect: Sendable, Equatable {
            case evaluate(Evaluation)
            case deliver(Response)
            case issuanceComplete
            case terminated(Failure)
            case inputRejected(Failure)
        }

        private(set) var phase: Phase = .collecting
        private let roster: OpalFusion.Mosaic.Attempt.Roster
        private var requests: [RequestKey: OpalCrypto.RSABSSA.BlindedMessage] = [:]
        private var responses: [RequestKey: OpalCrypto.RSABSSA.BlindSignature] = [:]

        init(roster: OpalFusion.Mosaic.Attempt.Roster) {
            self.roster = roster
        }

        mutating func apply(input: Input) -> [Effect] {
            if case .failed = phase {
                return [.inputRejected(.inputAfterTermination)]
            }

            switch input {
            case let .request(contributor, slot, blindedMessage):
                return receiveRequest(
                    contributor: contributor,
                    slot: slot,
                    blindedMessage: blindedMessage
                )
            case let .evaluated(response):
                return receiveEvaluation(response)
            case let .evaluationFailed(key):
                guard phase == .evaluating, requests[key] != nil else {
                    return terminate(with: .unexpectedEvaluationResult(key))
                }
                return terminate(with: .evaluationFailed(key))
            }
        }

        private mutating func receiveRequest(
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            slot: Int,
            blindedMessage: OpalCrypto.RSABSSA.BlindedMessage
        ) -> [Effect] {
            guard contributor != roster.conductor else {
                return terminate(with: .conductorSubmittedAuthorization)
            }
            guard roster.contributors.contains(contributor) else {
                return terminate(with: .unknownContributor)
            }
            guard (0 ..< OpalFusion.Mosaic.OpalV0.componentAuthorizationCountPerContributor)
                .contains(slot) else {
                return terminate(with: .invalidSlot(actual: slot))
            }

            let key = RequestKey(contributor: contributor, slot: slot)
            if let existingRequest = requests[key] {
                guard existingRequest == blindedMessage else {
                    return terminate(with: .conflictingSlotReuse(key))
                }
                if let blindSignature = responses[key] {
                    return [
                        .deliver(
                            Response(key: key, blindSignature: blindSignature)
                        )
                    ]
                }
                return []
            }

            guard phase == .collecting else {
                return terminate(with: .conflictingSlotReuse(key))
            }
            requests[key] = blindedMessage

            guard requests.count == expectedRequestCount else {
                return []
            }
            phase = .evaluating
            return sortedEvaluations.map(Effect.evaluate)
        }

        private mutating func receiveEvaluation(_ response: Response) -> [Effect] {
            guard phase == .evaluating || phase == .issued,
                  requests[response.key] != nil else {
                return terminate(with: .unexpectedEvaluationResult(response.key))
            }

            if let existingResponse = responses[response.key] {
                guard existingResponse == response.blindSignature else {
                    return terminate(with: .conflictingEvaluationResult(response.key))
                }
                return [.deliver(response)]
            }

            responses[response.key] = response.blindSignature
            var effects: [Effect] = [.deliver(response)]
            if responses.count == expectedRequestCount {
                phase = .issued
                effects.append(.issuanceComplete)
            }
            return effects
        }

        private var expectedRequestCount: Int {
            roster.contributors.count
                * OpalFusion.Mosaic.OpalV0.componentAuthorizationCountPerContributor
        }

        private var sortedEvaluations: [Evaluation] {
            requests.map { Evaluation(key: $0.key, blindedMessage: $0.value) }
                .sorted { lhs, rhs in
                    if lhs.key.contributor.validatedBytes
                        != rhs.key.contributor.validatedBytes {
                        return lhs.key.contributor.validatedBytes.lexicographicallyPrecedes(
                            rhs.key.contributor.validatedBytes
                        )
                    }
                    return lhs.key.slot < rhs.key.slot
                }
        }

        func issuedResponses(
            for contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            matching expectedRequests: [AuthorizationRequestPayload]
        ) throws -> [AuthorizationResponsePayload] {
            guard phase == .issued else {
                throw IssuedResponseError.issuanceIncomplete
            }
            guard roster.contributors.contains(contributor) else {
                throw IssuedResponseError.unknownContributor
            }
            guard expectedRequests.count
                == OpalFusion.Mosaic.OpalV0
                    .componentAuthorizationCountPerContributor else {
                throw IssuedResponseError.requestCountMismatch(
                    actual: expectedRequests.count
                )
            }
            return try (0 ..< OpalFusion.Mosaic.OpalV0
                .componentAuthorizationCountPerContributor).map { slot in
                let key = RequestKey(contributor: contributor, slot: slot)
                let expectedRequest = expectedRequests[slot]
                guard expectedRequest.slot == slot,
                      requests[key] == expectedRequest.blindedMessage else {
                    throw IssuedResponseError.requestMismatch(slot: slot)
                }
                guard let blindSignature = responses[key] else {
                    throw IssuedResponseError.issuanceIncomplete
                }
                return try AuthorizationResponsePayload(
                    slot: slot,
                    blindSignature: blindSignature
                )
            }
        }

        private mutating func terminate(with failure: Failure) -> [Effect] {
            phase = .failed(failure)
            return [.terminated(failure)]
        }
    }
}
