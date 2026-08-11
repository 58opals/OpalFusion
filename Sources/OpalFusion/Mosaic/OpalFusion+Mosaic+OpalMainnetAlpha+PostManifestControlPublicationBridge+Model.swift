// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestControlPublicationBridge+Model.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha.PostManifestControlPublicationBridge {
    typealias AttemptIdentifier = OpalFusion.Mosaic.LocalAttempt.AttemptIdentifier
    typealias GenerationIdentifier = OpalFusion.Mosaic.LocalAttempt.GenerationIdentifier
    typealias MaterialIdentifier = OpalFusion.Mosaic.LocalAttempt.MaterialIdentifier
    typealias ControlIdentity = OpalFusion.Mosaic.Attempt.ControlIdentity
    typealias Phase = OpalFusion.Mosaic.Attempt.Phase
    typealias Transport = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestNIP59Transport

    /// Immutable attempt facts owned by one sender-global control sequence.
    struct Context: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case runtimeBootstrapMismatch
            case manifestProposalMismatch
        }

        let attemptIdentifier: AttemptIdentifier
        let generationIdentifier: GenerationIdentifier
        let materialIdentifier: MaterialIdentifier
        let manifest: OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifest
        let localControlIdentity: ControlIdentity

        init(
            validating manifest: OpalFusion.Mosaic.OpalMainnetAlpha
                .RoundManifest,
            against bootstrap: OpalFusion.Mosaic.OpalMainnetAlpha
                .PostManifestRuntimeDriver.Bootstrap
        ) throws(ValidationError) {
            let runtimeContext: OpalFusion.Mosaic.OpalMainnetAlpha
                .RuntimeSession.Context
            do {
                runtimeContext = try OpalFusion.Mosaic.OpalMainnetAlpha
                    .RuntimeSession(
                        validatedAttempt: bootstrap.validatedAttempt,
                        attemptIdentifier: bootstrap.attemptIdentifier,
                        generationIdentifier: bootstrap.generationIdentifier,
                        materialIdentifier: bootstrap.materialIdentifier,
                        localControlIdentity: bootstrap.localControlIdentity,
                        proposalValidation: bootstrap.proposalValidation
                    ).context
            } catch {
                throw .runtimeBootstrapMismatch
            }
            guard manifest.core == bootstrap.proposalValidation.core else {
                throw .manifestProposalMismatch
            }
            attemptIdentifier = runtimeContext.attemptIdentifier
            generationIdentifier = runtimeContext.generationIdentifier
            materialIdentifier = runtimeContext.materialIdentifier
            self.manifest = manifest
            localControlIdentity = runtimeContext.localControlIdentity
        }

        var roundIdentifier: [UInt8] {
            manifest.core.roundIdentifier
        }

        var roster: OpalFusion.Mosaic.Attempt.Roster {
            manifest.core.roster
        }

        var phaseStartUnixSeconds: UInt64 {
            manifest.core.deadlines.phaseStart
        }
    }

    /// One externally allocated control-mailbox recipient for a roster identity.
    ///
    /// This value proves only exact, attempt-lifetime structural allocation. The caller remains
    /// responsible for authenticated key distribution, persistence, freshness, and erasure.
    struct Recipient: Sendable, Equatable {
        let controlIdentity: ControlIdentity
        let eventVerificationKey: OpalCrypto.Signature.BIP340.VerificationKey
    }

    struct TimestampRequest: Sendable, Equatable {
        let phase: Phase
        let sequence: UInt64
        let expiryUnixSeconds: UInt64
    }

    struct RecipientGiftWrap: Sendable, Equatable {
        let controlIdentity: ControlIdentity
        let giftWrap: OpalFusion.Mosaic.OpalMainnetAlpha
            .PostManifestRelayPublisher.GiftWrap
    }

    /// One signed control envelope wrapped once for every roster recipient.
    struct GiftWrapBatch: Sendable, Equatable {
        let envelope: OpalFusion.Mosaic.OpalMainnetAlpha.ControlEnvelope
        let recipients: [RecipientGiftWrap]
    }

    struct Dependencies: Sendable {
        /// Supplies caller-owned cover timestamps without defining a protocol clock policy.
        let makeLayerTimestamps: @Sendable (
            TimestampRequest
        ) throws -> Transport.LayerTimestamps

        /// Supplies fresh production signing randomness. Tests may inject deterministic values.
        let makeSignatureAuxiliaryRandomness: @Sendable () throws
            -> OpalCrypto.Signature.BIP340.AuxiliaryRandomness

        /// Hands one complete recipient batch to the transport owner.
        ///
        /// The operation must return only after every recipient's three-relay publisher has
        /// reached its two-ACK success boundary. It must not await semantic loopback admission or
        /// synchronously re-enter this bridge.
        let handoffGiftWrapBatch: @Sendable (GiftWrapBatch) async throws -> Void

        init(
            makeLayerTimestamps: @escaping @Sendable (
                TimestampRequest
            ) throws -> Transport.LayerTimestamps,
            makeSignatureAuxiliaryRandomness: @escaping @Sendable () throws
                -> OpalCrypto.Signature.BIP340.AuxiliaryRandomness = {
                    try .init(
                        rawRepresentation: OpalCrypto.SecureRandom.makeBytes(
                            count: 32
                        )
                    )
                },
            handoffGiftWrapBatch: @escaping @Sendable (
                GiftWrapBatch
            ) async throws -> Void
        ) {
            self.makeLayerTimestamps = makeLayerTimestamps
            self.makeSignatureAuxiliaryRandomness =
                makeSignatureAuxiliaryRandomness
            self.handoffGiftWrapBatch = handoffGiftWrapBatch
        }
    }

    enum InitializationError: Error, Sendable, Equatable {
        case controlSigningKeyMismatch
        case reusedControlAndEventIdentity
        case invalidRecipientCount(actual: Int)
        case duplicateRecipient(ControlIdentity)
        case recipientSetMismatch
        case duplicateRecipientEventIdentity
        case recipientEventIdentityReusesRosterControlIdentity
        case recipientEventIdentityReusesSenderEventIdentity
    }

    struct SequenceReservation: Sendable, Equatable {
        let firstSequence: UInt64
        let envelopeCount: Int
        let nextSequence: UInt64
        let phase: Phase
    }

    enum State: Sendable, Equatable {
        case ready(nextSequence: UInt64, lastPublishedPhase: Phase?)
        case publishing(SequenceReservation)
        case terminal(Failure)
    }

    enum Failure: Error, Sendable, Equatable {
        case invalidFirstPublication
        case invalidPublication
        case phaseRollback(previous: Phase, next: Phase)
        case sequenceExhausted
        case signatureConstructionFailed
        case giftWrapConstructionFailed
        case handoffFailed
        case concurrentPublication
        case cancelled
        case inputAfterTermination
    }
}

extension OpalFusion.Mosaic.OpalMainnetAlpha.ConductorCoordinator.Publication {
    var aggregateDocument: OpalFusion.Mosaic.OpalMainnetAlpha.AggregateDocument {
        switch self {
        case let .authorizationResponseSet(responseSet):
            .authorizationResponseSet(responseSet)
        case let .commitmentSet(commitmentSet):
            .commitmentSet(commitmentSet)
        case let .componentSet(componentSet):
            .componentSet(componentSet)
        case let .preSignAcknowledgementSet(acknowledgementSet):
            .preSignAcknowledgementSet(acknowledgementSet)
        case let .bchSignatureSet(signatureSet):
            .bchSignatureSet(signatureSet)
        case let .completeTransaction(transaction):
            .completeTransaction(transaction)
        }
    }
}
