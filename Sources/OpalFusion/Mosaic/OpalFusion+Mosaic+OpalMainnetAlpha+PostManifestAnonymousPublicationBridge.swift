// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestAnonymousPublicationBridge.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Converts one contributor's material-bound anonymous publications into alpha.5 gift wraps.
    ///
    /// The bridge enforces component sequence zero and BCH-signature sequence one on the same
    /// mailboxes with distinct one-time sender identities. It owns no route selection, timing
    /// policy, persistence, retry, semantic loopback, wallet authority, or broadcast permission.
    actor PostManifestAnonymousPublicationBridge {
        struct RecipientGiftWrap: Sendable, Equatable {
            let recipientEventIdentity: Data
            let giftWrap: OpalFusion.Mosaic.OpalMainnetAlpha
                .PostManifestRelayPublisher.GiftWrap

            fileprivate init(
                recipientEventIdentity: Data,
                giftWrap: OpalFusion.Mosaic.OpalMainnetAlpha
                    .PostManifestRelayPublisher.GiftWrap
            ) {
                self.recipientEventIdentity = recipientEventIdentity
                self.giftWrap = giftWrap
            }
        }

        /// One bridge-minted, purpose-specific anonymous publication handoff.
        struct GiftWrapBatch: Sendable, Equatable {
            private let context: Context
            private let materialBinding: MaterialBinding
            let kind: PublicationKind
            let recipients: [RecipientGiftWrap]

            fileprivate init(
                context: Context,
                materialBinding: MaterialBinding,
                kind: PublicationKind,
                recipients: [RecipientGiftWrap]
            ) {
                self.context = context
                self.materialBinding = materialBinding
                self.kind = kind
                self.recipients = recipients
            }

            func isBound(
                to context: Context,
                materialBinding: MaterialBinding
            ) -> Bool {
                self.context == context
                    && self.materialBinding == materialBinding
            }
        }

        private struct EnvelopeMaterial: Sendable {
            let recipientEventIdentity: Data
            let senderPrivateKey: OpalCrypto.Secp256k1.PrivateKey
            let phase: OpalFusion.Mosaic.Attempt.Phase
            let sequence: UInt64
            let payloadType: AnonymousPayloadType
            let payload: [UInt8]
        }

        private let context: Context
        private let expectedMaterialBinding: MaterialBinding
        private let dependencies: Dependencies
        private var componentRecipientIdentities: Set<Data> = []

        private(set) var state: State = .readyForComponents

        init(
            context: Context,
            material: LocalContributionMaterial,
            dependencies: Dependencies
        ) throws(InitializationError) {
            guard context.roster.contributors.contains(
                context.localControlIdentity
            ) else {
                throw .localPeerIsNotContributor
            }
            guard context.attemptIdentifier == material.attemptIdentifier,
                  context.generationIdentifier
                    == material.generationIdentifier,
                  context.materialIdentifier == material.materialIdentifier,
                  context.localControlIdentity == material.contributor,
                  context.manifest == material.manifest else {
                throw .localMaterialMismatch
            }
            self.context = context
            expectedMaterialBinding = .init(material: material)
            self.dependencies = dependencies
        }

        /// Publishes all 23 component envelopes at mailbox sequence zero.
        func publishComponents(
            _ validation: ComponentValidation,
            expiryUnixSeconds: UInt64
        ) async throws(Failure) {
            try begin(.components)
            guard validation.context == context,
                  validation.materialBinding == expectedMaterialBinding,
                  validateMaterialBinding(validation.materialBinding),
                  validateComponentEntries(
                    validation.entries,
                    against: validation.materialBinding
                  ) else {
                throw terminate(.invalidPublication)
            }

            let materials: [EnvelopeMaterial]
            do {
                materials = try validation.entries.map { entry in
                    .init(
                        recipientEventIdentity: Data(
                            entry.recipientEventIdentity
                        ),
                        senderPrivateKey: entry.senderPrivateKey,
                        phase: .anonymousComponentSubmission,
                        sequence: 0,
                        payloadType: .anonymousComponent,
                        payload: try CanonicalWireCodec
                            .encodeAnonymousComponent(entry.payload)
                    )
                }
            } catch {
                if Task.isCancelled {
                    throw terminate(.cancelled)
                }
                throw terminate(.giftWrapConstructionFailed)
            }

            try await handoff(
                materials,
                kind: .components,
                expiryUnixSeconds: expiryUnixSeconds
            )
            guard state == .publishing(.components) else {
                throw terminalFailure()
            }
            componentRecipientIdentities = Set(
                validation.entries.map { Data($0.recipientEventIdentity) }
            )
            state = .componentsPublished
        }

        /// Publishes the locally produced input-signature subset at mailbox sequence one.
        func publishBCHSignatures(
            _ validation: BCHSignatureValidation,
            expiryUnixSeconds: UInt64
        ) async throws(Failure) {
            try begin(.bchSignatures)
            guard validation.context == context,
                  validation.materialBinding == expectedMaterialBinding,
                  validateBCHSignatureEntries(
                    validation.entries,
                    against: validation.materialBinding
                  ) else {
                throw terminate(.invalidPublication)
            }

            let materials = validation.entries.map { entry in
                EnvelopeMaterial(
                    recipientEventIdentity: Data(
                        entry.recipientEventIdentity
                    ),
                    senderPrivateKey: entry.senderPrivateKey,
                    phase: .bchSigning,
                    sequence: 1,
                    payloadType: .bchSignatureSubmission,
                    payload: entry.submission.canonicalBytes
                )
            }
            try await handoff(
                materials,
                kind: .bchSignatures,
                expiryUnixSeconds: expiryUnixSeconds
            )
            guard state == .publishing(.bchSignatures) else {
                throw terminalFailure()
            }
            state = .completed
        }

        private func begin(_ kind: PublicationKind) throws(Failure) {
            switch state {
            case .terminal, .completed:
                throw .inputAfterTermination
            case .readyForComponents, .publishing, .componentsPublished:
                break
            }
            try failIfCancelled()
            switch (state, kind) {
            case (.readyForComponents, .components),
                 (.componentsPublished, .bchSignatures):
                state = .publishing(kind)
            case (.publishing, _):
                throw terminate(.concurrentPublication)
            case (.readyForComponents, .bchSignatures),
                 (.componentsPublished, .components):
                throw terminate(.invalidOrder)
            case (.terminal, _), (.completed, _):
                preconditionFailure(
                    "Terminal publication state was handled before cancellation."
                )
            }
        }

        private func handoff(
            _ materials: [EnvelopeMaterial],
            kind: PublicationKind,
            expiryUnixSeconds: UInt64
        ) async throws(Failure) {
            try failIfCancelled()
            let batch: GiftWrapBatch
            do {
                let transportContext = Transport.RuntimeContext(
                    attemptIdentifier: context.attemptIdentifier,
                    generationIdentifier: context.generationIdentifier,
                    phaseStartUnixSeconds: context.phaseStartUnixSeconds
                )
                let recipients = try materials.map { material in
                    let senderSigningKey = material.senderPrivateKey
                        .makeSigningKey()
                    let recipientKey = try OpalCrypto.Signature.BIP340
                        .VerificationKey(
                            rawRepresentation:
                                material.recipientEventIdentity
                        )
                    let timestamps = try dependencies.makeLayerTimestamps(
                        .init(
                            recipientEventIdentity:
                                material.recipientEventIdentity,
                            phase: material.phase,
                            sequence: material.sequence,
                            expiryUnixSeconds: expiryUnixSeconds
                        )
                    )
                    let envelope = try AnonymousEnvelope(
                        roundIdentifier: context.roundIdentifier,
                        phase: material.phase,
                        senderCommunicationPublicKey: [UInt8](
                            senderSigningKey.publicKey
                                .compressedRepresentation
                        ),
                        recipientEventIdentity: [UInt8](
                            material.recipientEventIdentity
                        ),
                        sequence: material.sequence,
                        payloadType: material.payloadType,
                        expiryUnixSeconds: expiryUnixSeconds,
                        payload: material.payload
                    )
                    let event = try Transport.makeAnonymousGiftWrap(
                        envelope,
                        context: transportContext,
                        timestamps: timestamps,
                        senderCommunicationSigningKey: senderSigningKey,
                        recipientPublicKey: recipientKey
                    )
                    return RecipientGiftWrap(
                        recipientEventIdentity:
                            material.recipientEventIdentity,
                        giftWrap: try .init(validating: event)
                    )
                }
                batch = .init(
                    context: context,
                    materialBinding: expectedMaterialBinding,
                    kind: kind,
                    recipients: recipients
                )
            } catch {
                if Task.isCancelled {
                    throw terminate(.cancelled)
                }
                throw terminate(.giftWrapConstructionFailed)
            }

            do {
                try failIfCancelled()
                try await dependencies.handoffGiftWrapBatch(batch)
            } catch {
                if Task.isCancelled {
                    throw terminate(.cancelled)
                }
                throw terminate(.handoffFailed)
            }
            try failIfCancelled()
        }

        private func validateMaterialBinding(
            _ binding: MaterialBinding
        ) -> Bool {
            guard binding.slots.count == componentCountPerContributor else {
                return false
            }
            let controlIdentities = Set(
                context.roster.controlIdentities.map {
                    Data($0.validatedBytes)
                }
            )
            var oneTimeIdentities: Set<Data> = []
            for slot in binding.slots {
                let identities = [
                    slot.recipientEventIdentity,
                    slot.groupedCommunicationIdentity,
                    slot.componentEnvelopeIdentity,
                    slot.bchSignatureEnvelopeIdentity,
                ]
                guard identities.allSatisfy({ identity in
                    identity.count
                        == OpalFusion.Mosaic.OpalV0.digestByteCount
                        && !controlIdentities.contains(identity)
                        && oneTimeIdentities.insert(identity).inserted
                }) else {
                    return false
                }
            }
            return true
        }

        private func validateComponentEntries(
            _ entries: [ComponentValidation.Entry],
            against binding: MaterialBinding
        ) -> Bool {
            guard entries.count == binding.slots.count else { return false }
            let bindingByRecipient = Dictionary(
                uniqueKeysWithValues: binding.slots.map {
                    ($0.recipientEventIdentity, $0)
                }
            )
            var recipients: Set<Data> = []
            for entry in entries {
                let recipient = Data(entry.recipientEventIdentity)
                let sender = Data(
                    entry.senderPrivateKey.makeSigningKey().publicKey
                        .compressedRepresentation.dropFirst()
                )
                guard recipients.insert(recipient).inserted,
                      bindingByRecipient[recipient]?
                        .componentEnvelopeIdentity == sender else {
                    return false
                }
            }
            return recipients == Set(bindingByRecipient.keys)
        }

        private func validateBCHSignatureEntries(
            _ entries: [BCHSignatureValidation.Entry],
            against binding: MaterialBinding
        ) -> Bool {
            guard !entries.isEmpty else { return false }
            let bindingByRecipient = Dictionary(
                uniqueKeysWithValues: binding.slots.map {
                    ($0.recipientEventIdentity, $0)
                }
            )
            var recipients: Set<Data> = []
            for entry in entries {
                let recipient = Data(entry.recipientEventIdentity)
                let sender = Data(
                    entry.senderPrivateKey.makeSigningKey().publicKey
                        .compressedRepresentation.dropFirst()
                )
                guard componentRecipientIdentities.contains(recipient),
                      recipients.insert(recipient).inserted,
                      bindingByRecipient[recipient]?
                        .bchSignatureEnvelopeIdentity == sender else {
                    return false
                }
            }
            return true
        }

        private func failIfCancelled() throws(Failure) {
            guard !Task.isCancelled else {
                throw terminate(.cancelled)
            }
        }

        private func terminalFailure() -> Failure {
            guard case let .terminal(failure) = state else {
                preconditionFailure(
                    "An in-flight anonymous publication can change only by terminalization."
                )
            }
            return failure
        }

        @discardableResult
        private func terminate(_ failure: Failure) -> Failure {
            if case let .terminal(existing) = state {
                return existing
            }
            state = .terminal(failure)
            return failure
        }
    }
}
