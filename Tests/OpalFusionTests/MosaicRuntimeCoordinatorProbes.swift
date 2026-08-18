// MosaicRuntimeCoordinatorProbes.swift

import Foundation
@testable import OpalFusion

actor MosaicRuntimeCoordinatorSuspensionProbe {
    private var isArmed = false
    private var hasSuspended = false
    private let waitsForExplicitResumeAfterCancellation: Bool
    private var hasResumed = false
    private var explicitResumeContinuation: CheckedContinuation<Void, Never>?
    private let suspendedStream: AsyncStream<Void>
    private let suspendedContinuation: AsyncStream<Void>.Continuation
    private let resumeStream: AsyncStream<Void>
    private let resumeContinuation: AsyncStream<Void>.Continuation

    init(waitsForExplicitResumeAfterCancellation: Bool = false) {
        self.waitsForExplicitResumeAfterCancellation =
            waitsForExplicitResumeAfterCancellation
        (suspendedStream, suspendedContinuation) = AsyncStream<Void>
            .makeStream(bufferingPolicy: .bufferingNewest(1))
        (resumeStream, resumeContinuation) = AsyncStream<Void>
            .makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func arm() {
        isArmed = true
    }

    func suspendIfArmed() async {
        guard isArmed, !hasSuspended else {
            return
        }
        hasSuspended = true
        suspendedContinuation.yield()
        if waitsForExplicitResumeAfterCancellation {
            guard !hasResumed else { return }
            await withCheckedContinuation { continuation in
                explicitResumeContinuation = continuation
            }
        } else {
            for await _ in resumeStream {
                return
            }
        }
    }

    func waitUntilSuspended() async {
        guard !hasSuspended else {
            return
        }
        for await _ in suspendedStream {
            return
        }
    }

    func resume() {
        hasResumed = true
        explicitResumeContinuation?.resume()
        explicitResumeContinuation = nil
        resumeContinuation.yield()
    }
}

actor MosaicRuntimeCoordinatorSignalProbe {
    enum Signal: Hashable, Sendable {
        case reservationPublished
        case preSignPublished
        case localSignaturesPublished
    }

    enum ProbeFailure: Error {
        case injected
    }

    private var counts: [Signal: Int] = [:]
    private var waiters: [Signal: [CheckedContinuation<Void, Never>]] = [:]
    private var failingSignals: Set<Signal> = []

    func fail(_ signal: Signal) {
        failingSignals.insert(signal)
    }

    func record(_ signal: Signal) throws {
        guard !failingSignals.contains(signal) else {
            throw ProbeFailure.injected
        }
        counts[signal, default: 0] += 1
        let continuations = waiters.removeValue(forKey: signal) ?? []
        for continuation in continuations {
            continuation.resume()
        }
    }

    func wait(for signal: Signal) async {
        guard counts[signal, default: 0] > 0 else {
            await withCheckedContinuation { continuation in
                waiters[signal, default: []].append(continuation)
            }
            return
        }
    }

    func count(_ signal: Signal) -> Int {
        counts[signal, default: 0]
    }
}

actor MosaicRuntimeCoordinatorHostProbe:
    OpalFusion.Host.MosaicCompleteTransactionHost {
    enum ProbeFailure: Error {
        case reservation
        case completeCommit
        case release
    }

    let lease: OpalFusion.Host.MosaicReservationLease
    let finalizedTransaction: OpalFusion.Host.FinalizedTransaction
    let reserveSuspension: MosaicRuntimeCoordinatorSuspensionProbe?
    let signingSuspension: MosaicRuntimeCoordinatorSuspensionProbe?
    let completeCommitSuspension: MosaicRuntimeCoordinatorSuspensionProbe?

    private var shouldFailReservation = false
    private var shouldFailCompleteCommit = false
    private var shouldFailRelease = false
    private(set) var reservationRequests: [
        OpalFusion.Host.MosaicReservationRequest
    ] = []
    private(set) var signingRequests: [
        OpalFusion.Host.MosaicTransactionSigningRequest
    ] = []
    private(set) var releasedReferences: [
        OpalFusion.Host.MosaicReservationReference
    ] = []
    private(set) var completeCommits: [(
        OpalFusion.Host.MosaicReservationReference,
        OpalFusion.Host.MosaicCompleteTransaction
    )] = []
    private(set) var legacyCommitCount = 0

    init(
        lease: OpalFusion.Host.MosaicReservationLease,
        finalizedTransaction: OpalFusion.Host.FinalizedTransaction,
        reserveSuspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil,
        signingSuspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil,
        completeCommitSuspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil
    ) {
        self.lease = lease
        self.finalizedTransaction = finalizedTransaction
        self.reserveSuspension = reserveSuspension
        self.signingSuspension = signingSuspension
        self.completeCommitSuspension = completeCommitSuspension
    }

    func failCompleteCommit() {
        shouldFailCompleteCommit = true
    }

    func failReservation() {
        shouldFailReservation = true
    }

    func failRelease() {
        shouldFailRelease = true
    }

    func reserveMosaicContribution(
        for request: OpalFusion.Host.MosaicReservationRequest
    ) async throws -> OpalFusion.Host.MosaicReservationLease {
        reservationRequests.append(request)
        await reserveSuspension?.suspendIfArmed()
        guard !shouldFailReservation else {
            throw ProbeFailure.reservation
        }
        return lease
    }

    func finalizeMosaicTransaction(
        for request: OpalFusion.Host.MosaicTransactionSigningRequest
    ) async throws -> OpalFusion.Host.FinalizedTransaction {
        signingRequests.append(request)
        await signingSuspension?.suspendIfArmed()
        return finalizedTransaction
    }

    func releaseMosaicReservation(
        _ reservationReference: OpalFusion.Host.MosaicReservationReference
    ) async throws {
        releasedReferences.append(reservationReference)
        guard !shouldFailRelease else {
            throw ProbeFailure.release
        }
    }

    func commitMosaicReservation(
        _ reservationReference: OpalFusion.Host.MosaicReservationReference,
        finalizedTransaction: OpalFusion.Host.FinalizedTransaction
    ) async throws {
        legacyCommitCount += 1
    }

    func commitMosaicReservation(
        _ reservationReference: OpalFusion.Host.MosaicReservationReference,
        completeTransaction: OpalFusion.Host.MosaicCompleteTransaction
    ) async throws {
        await completeCommitSuspension?.suspendIfArmed()
        guard !shouldFailCompleteCommit else {
            throw ProbeFailure.completeCommit
        }
        completeCommits.append((reservationReference, completeTransaction))
    }
}
