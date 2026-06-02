// OpalDiagnostics+Event+OpalFusion.swift

import Foundation
import OpalDiagnostics

extension OpalDiagnostics.Event {
    static let primaryConnectStarted = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connect.started")
    static let primaryConnectSucceeded = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connect.succeeded")
    static let primaryConnectFailed = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connect.failed")
    static let primaryConnectionPreparing = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connection.preparing")
    static let primaryConnectionReady = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connection.ready")
    static let primaryConnectionWaiting = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connection.waiting")
    static let primaryConnectionCancelled = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connection.cancelled")
    static let primaryConnectionPeerEOF = OpalDiagnostics.Event(rawValue: "opalfusion.primary.connection.peer_eof")
    static let primaryMessageSent = OpalDiagnostics.Event(rawValue: "opalfusion.primary.message.sent")
    static let primaryMessageReceived = OpalDiagnostics.Event(rawValue: "opalfusion.primary.message.received")
    static let primaryMessageEncodeFailed = OpalDiagnostics.Event(rawValue: "opalfusion.primary.message.encode.failed")
    static let primaryMessageDecodeFailed = OpalDiagnostics.Event(rawValue: "opalfusion.primary.message.decode.failed")
    static let primaryRetryScheduled = OpalDiagnostics.Event(rawValue: "opalfusion.primary.retry.scheduled")
    static let handshakePhaseChanged = OpalDiagnostics.Event(rawValue: "opalfusion.handshake.phase.changed")

    static let covertPrepareStarted = OpalDiagnostics.Event(rawValue: "opalfusion.covert.prepare.started")
    static let covertPrepareSucceeded = OpalDiagnostics.Event(rawValue: "opalfusion.covert.prepare.succeeded")
    static let covertPrepareFailed = OpalDiagnostics.Event(rawValue: "opalfusion.covert.prepare.failed")
    static let covertRequestStarted = OpalDiagnostics.Event(rawValue: "opalfusion.covert.request.started")
    static let covertRequestSucceeded = OpalDiagnostics.Event(rawValue: "opalfusion.covert.request.succeeded")
    static let covertRequestFailed = OpalDiagnostics.Event(rawValue: "opalfusion.covert.request.failed")
    static let covertMessageEncodeFailed = OpalDiagnostics.Event(rawValue: "opalfusion.covert.message.encode.failed")
    static let covertResponseDecodeFailed = OpalDiagnostics.Event(rawValue: "opalfusion.covert.response.decode.failed")

    static let roundEntered = OpalDiagnostics.Event(rawValue: "opalfusion.round.entered")
    static let roundProgressed = OpalDiagnostics.Event(rawValue: "opalfusion.round.progressed")
    static let roundCompleted = OpalDiagnostics.Event(rawValue: "opalfusion.round.completed")
    static let roundFailed = OpalDiagnostics.Event(rawValue: "opalfusion.round.failed")
    static let roundRestarted = OpalDiagnostics.Event(rawValue: "opalfusion.round.restarted")

    static let transactionProposalFailed = OpalDiagnostics.Event(rawValue: "opalfusion.transaction.proposal.failed")
    static let transactionFinalizationSucceeded = OpalDiagnostics.Event(rawValue: "opalfusion.transaction.finalization.succeeded")
    static let transactionFinalizationFailed = OpalDiagnostics.Event(rawValue: "opalfusion.transaction.finalization.failed")

    static let blameProofValidationFailed = OpalDiagnostics.Event(rawValue: "opalfusion.blame.proof_validation.failed")
    static let blameSubmissionStarted = OpalDiagnostics.Event(rawValue: "opalfusion.blame.submission.started")

    static let transportError = OpalDiagnostics.Event(rawValue: "opalfusion.transport.error")
}
