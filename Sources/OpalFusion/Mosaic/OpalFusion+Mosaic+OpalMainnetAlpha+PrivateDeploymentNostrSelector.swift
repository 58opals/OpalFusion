// OpalFusion+Mosaic+OpalMainnetAlpha+PrivateDeploymentNostrSelector.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Internal selector and event-kind table for private-deployment coordination.
    struct PrivateDeploymentNostrSelector: Sendable, Equatable {
        enum PayloadKind: UInt8, Sendable, Equatable {
            case availabilityBeacon = 0
            case candidateSetAcknowledgement = 1
            case candidateAdmission = 2
            case roleCommitment = 3
            case roleReveal = 4
            case contributorNonceAllocation = 5
            case manifestProposal = 6
            case manifestSignature = 7
            case abort = 8
            case completion = 9
        }

        enum SignerRole: UInt8, Sendable, Equatable {
            case discovery = 0
            case control = 1
            case conductor = 2
        }

        static let privateDeployment = Self()
        static let identifier =
            "nostr-tor/0-opal-mainnet-alpha-private-deployment.1"
        static var identifierBytes: [UInt8] { Array(identifier.utf8) }

        private init() {}

        func eventKind(for payloadKind: PayloadKind) -> UInt16 {
            switch payloadKind {
            case .availabilityBeacon: 26_540
            case .candidateSetAcknowledgement: 26_541
            case .candidateAdmission: 26_542
            case .roleCommitment: 26_543
            case .roleReveal: 26_544
            case .contributorNonceAllocation: 26_546
            case .manifestProposal, .manifestSignature: 26_545
            case .abort: 26_547
            case .completion: 26_548
            }
        }

        func allows(
            signerRole: SignerRole,
            for payloadKind: PayloadKind
        ) -> Bool {
            switch payloadKind {
            case .availabilityBeacon,
                 .candidateSetAcknowledgement,
                 .candidateAdmission:
                signerRole == .discovery
            case .roleCommitment, .roleReveal:
                signerRole == .control
            case .contributorNonceAllocation, .manifestProposal, .completion:
                signerRole == .conductor
            case .manifestSignature:
                signerRole == .control || signerRole == .conductor
            case .abort:
                true
            }
        }
    }
}
