// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestTransportIngress+Model.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha.PostManifestTransportIngress {
    typealias Driver = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestRuntimeDriver
    typealias Transport = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestNIP59Transport

    /// Immutable decryption authorities admitted for one attempt-scoped ingress.
    struct RecipientSet: Sendable {
        enum ValidationError: Error, Sendable, Equatable {
            case empty
            case duplicateRecipientIdentity
        }

        private let capabilitiesByIdentity: [
            Data: Transport.RecipientCapability
        ]

        init(
            _ capabilities: [Transport.RecipientCapability]
        ) throws(ValidationError) {
            guard !capabilities.isEmpty else { throw .empty }
            var capabilitiesByIdentity: [
                Data: Transport.RecipientCapability
            ] = [:]
            for capability in capabilities {
                let identity = capability.recipientEventIdentity
                guard capabilitiesByIdentity[identity] == nil else {
                    throw .duplicateRecipientIdentity
                }
                capabilitiesByIdentity[identity] = capability
            }
            self.capabilitiesByIdentity = capabilitiesByIdentity
        }

        init(_ capability: Transport.RecipientCapability) {
            capabilitiesByIdentity = [
                capability.recipientEventIdentity: capability,
            ]
        }

        func capability(
            for recipientEventIdentity: Data
        ) -> Transport.RecipientCapability? {
            capabilitiesByIdentity[recipientEventIdentity]
        }
    }

    struct Dependencies: Sendable {
        let currentUnixSeconds: @Sendable () -> UInt64
        let beforeDriverStart: @Sendable () async -> Void

        init(
            currentUnixSeconds: @escaping @Sendable () -> UInt64,
            beforeDriverStart: @escaping @Sendable () async -> Void = {}
        ) {
            self.currentUnixSeconds = currentUnixSeconds
            self.beforeDriverStart = beforeDriverStart
        }
    }

    enum InitializationError: Error, Sendable, Equatable {
        case runtimeDriver(Driver.InitializationError)
    }

    enum State: Sendable, Equatable {
        case idle
        case starting
        case running
        case stopping
        case terminal(Driver.State)
    }

    enum Rejection: Error, Sendable, Equatable {
        case notRunning
        case unknownRecipient
        case transport(Transport.Failure)
        case runtimeRejected
    }

    enum Decision: Sendable, Equatable {
        case accepted
        case rejected(Rejection)
    }
}
