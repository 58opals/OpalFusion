// OpalFusion+Mosaic+NIP01RelaySession+Failure.swift

extension OpalFusion.Mosaic.NIP01RelaySession {
    enum Failure: Error, Sendable, Equatable {
        case invalidOutputBufferLimit
        case alreadyStarted
        case notRunning
        case duplicateSubscription(
            OpalFusion.Mosaic.NostrNamespace.SubscriptionIdentifier
        )
        case unknownSubscription(
            OpalFusion.Mosaic.NostrNamespace.SubscriptionIdentifier
        )
        case duplicatePublication
        case unsolicitedAcknowledgement
        case binaryFrameReceived
        case malformedRelayFrame
        case outputBufferOverflow
        case transportFailure
    }
}
