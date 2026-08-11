// OpalFusion+Mosaic+OpalMainnetAlpha+ReservationCoordinator+AnonymousPublicationValidation.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha.ReservationCoordinator {
    typealias AnonymousPublicationContext = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestControlPublicationBridge.Context

    enum AnonymousPublicationValidationError: Error, Sendable, Equatable {
        case contextMismatch
        case invalidComponentCount(actual: Int)
        case duplicateComponentSlot(Int)
        case componentMismatch(slot: Int)
        case transcriptMismatch
        case invalidBCHSignatureCount(actual: Int)
        case duplicateBCHSignatureSlot(Int)
        case bchSignatureMismatch(slot: Int)
    }

    struct AnonymousMaterialBinding: Sendable, Equatable {
        struct Slot: Sendable, Equatable {
            let recipientEventIdentity: Data
            let groupedCommunicationIdentity: Data
            let componentEnvelopeIdentity: Data
            let bchSignatureEnvelopeIdentity: Data
        }

        let playerCommitDigest: [UInt8]
        let slots: [Slot]

        init(
            material: OpalFusion.Mosaic.OpalMainnetAlpha
                .LocalContributionMaterial
        ) {
            playerCommitDigest = material.playerCommit.digest
            slots = material.slots.map { slot in
                .init(
                    recipientEventIdentity: Data(
                        slot.recipientEventIdentity
                    ),
                    groupedCommunicationIdentity: Data(
                        slot.communicationPrivateKey.makeSigningKey()
                            .publicKey.compressedRepresentation.dropFirst()
                    ),
                    componentEnvelopeIdentity: Data(
                        slot.componentEnvelopePrivateKey.makeSigningKey()
                            .publicKey.compressedRepresentation.dropFirst()
                    ),
                    bchSignatureEnvelopeIdentity: Data(
                        slot.bchSignatureEnvelopePrivateKey.makeSigningKey()
                            .publicKey.compressedRepresentation.dropFirst()
                    )
                )
            }
        }
    }

    struct AnonymousComponentPublicationValidation: Sendable {
        struct Entry: Sendable {
            let slot: Int
            let recipientEventIdentity: [UInt8]
            let senderPrivateKey: OpalCrypto.Secp256k1.PrivateKey
            let payload: OpalFusion.Mosaic.OpalMainnetAlpha
                .AnonymousComponentPayload
        }

        let context: AnonymousPublicationContext
        let materialBinding: AnonymousMaterialBinding
        let entries: [Entry]

        init(
            validating publications: [LocalAnonymousComponentPublication],
            material: OpalFusion.Mosaic.OpalMainnetAlpha
                .LocalContributionMaterial,
            runtimeContext: Session.Context
        ) throws(AnonymousPublicationValidationError) {
            let context: AnonymousPublicationContext
            do {
                context = try .init(
                    validating: material,
                    against: runtimeContext
                )
            } catch {
                throw .contextMismatch
            }
            guard publications.count
                    == OpalFusion.Mosaic.OpalMainnetAlpha
                        .componentCountPerContributor else {
                throw .invalidComponentCount(actual: publications.count)
            }

            var publicationsBySlot: [Int: LocalAnonymousComponentPublication]
                = [:]
            for publication in publications {
                guard publicationsBySlot.updateValue(
                    publication,
                    forKey: publication.slot
                ) == nil else {
                    throw .duplicateComponentSlot(publication.slot)
                }
            }

            var entries: [Entry] = []
            entries.reserveCapacity(material.slots.count)
            for slot in material.slots {
                let expectedBinding: [UInt8]
                do {
                    expectedBinding = try Self.componentBinding(for: slot)
                } catch {
                    throw .componentMismatch(slot: slot.slot)
                }
                guard let publication = publicationsBySlot[slot.slot],
                      publication.recipientEventIdentity
                        == slot.recipientEventIdentity,
                      publication.payload.roundIdentifier
                        == material.manifest.core.roundIdentifier,
                      publication.payload.component == slot.component,
                      publication.payload.authorizationToken.input
                        == slot.componentAuthorizationRequest.input,
                      publication.payload.authorizationToken.verify(
                        purpose: .component,
                        binding: expectedBinding,
                        using: material.manifest.core
                            .componentAuthorizationVerificationKey
                      ) else {
                    throw .componentMismatch(slot: slot.slot)
                }
                entries.append(
                    .init(
                        slot: slot.slot,
                        recipientEventIdentity: slot.recipientEventIdentity,
                        senderPrivateKey: slot.componentEnvelopePrivateKey,
                        payload: publication.payload
                    )
                )
            }

            self.context = context
            materialBinding = .init(material: material)
            self.entries = entries.sorted {
                $0.recipientEventIdentity.lexicographicallyPrecedes(
                    $1.recipientEventIdentity
                )
            }
        }

        private static func componentBinding(
            for slot: OpalFusion.Mosaic.OpalMainnetAlpha.ComponentSlotMaterial
        ) throws -> [UInt8] {
            try OpalFusion.Mosaic.OpalMainnetAlpha.AuthorizationTokenInput
                .componentBinding(for: slot.component)
        }
    }

    struct AnonymousBCHSignaturePublicationValidation: Sendable {
        struct Entry: Sendable {
            let slot: Int
            let recipientEventIdentity: [UInt8]
            let senderPrivateKey: OpalCrypto.Secp256k1.PrivateKey
            let submission: OpalFusion.Mosaic.OpalMainnetAlpha
                .BCHSignatureSubmission
        }

        let context: AnonymousPublicationContext
        let materialBinding: AnonymousMaterialBinding
        let transcriptRoot: OpalFusion.Mosaic.Attempt.TranscriptRoot
        let entries: [Entry]

        init(
            validating publications: [OpalFusion.Mosaic.OpalMainnetAlpha
                .LocalBCHSignaturePublication],
            transcriptInclusion: OpalFusion.Mosaic.LocalAttempt
                .TranscriptInclusionValidation,
            material: OpalFusion.Mosaic.OpalMainnetAlpha
                .LocalContributionMaterial,
            runtimeContext: Session.Context
        ) throws(AnonymousPublicationValidationError) {
            let context: AnonymousPublicationContext
            do {
                context = try .init(
                    validating: material,
                    against: runtimeContext
                )
            } catch {
                throw .contextMismatch
            }
            do {
                try material.validateCompleteInclusion(
                    attemptIdentifier:
                        transcriptInclusion.attemptIdentifier,
                    generationIdentifier:
                        transcriptInclusion.generationIdentifier,
                    contributor: transcriptInclusion.contributor,
                    materialIdentifier:
                        transcriptInclusion.materialIdentifier,
                    transcript: transcriptInclusion.transcript
                )
            } catch {
                throw .transcriptMismatch
            }
            guard transcriptInclusion.attemptIdentifier
                    == material.attemptIdentifier,
                  transcriptInclusion.generationIdentifier
                    == material.generationIdentifier,
                  transcriptInclusion.materialIdentifier
                    == material.materialIdentifier,
                  transcriptInclusion.contributor == material.contributor,
                  transcriptInclusion.transcript.manifest
                    == material.manifest.binding else {
                throw .transcriptMismatch
            }

            let transcript = transcriptInclusion.transcript
            let inputIndexByOutpoint = Self.inputIndexByOutpoint(
                in: transcript
            )
            let inputSlots = material.slots.filter {
                if case .input = $0.component.payload {
                    return true
                }
                return false
            }
            var publicationsBySlot: [Int: OpalFusion.Mosaic.OpalMainnetAlpha
                .LocalBCHSignaturePublication] = [:]
            for publication in publications {
                guard publicationsBySlot.updateValue(
                    publication,
                    forKey: publication.slot
                ) == nil else {
                    throw .duplicateBCHSignatureSlot(publication.slot)
                }
            }
            guard publications.count == inputSlots.count else {
                throw .invalidBCHSignatureCount(actual: publications.count)
            }

            var entries: [Entry] = []
            entries.reserveCapacity(inputSlots.count)
            for slot in inputSlots {
                guard case let .input(input) = slot.component.payload,
                      let expectedInputIndex = inputIndexByOutpoint[
                        .init(
                            transactionHash: input.previousTransactionHash,
                            outputIndex: input.outputIndex
                        )
                      ],
                      let publication = publicationsBySlot[slot.slot],
                      publication.recipientEventIdentity
                        == slot.recipientEventIdentity,
                      publication.submission.transcriptRoot
                        == transcript.transcriptRoot.validatedBytes,
                      publication.submission.entry.inputIndex
                        == UInt32(expectedInputIndex),
                      publication.submission.authorizationToken.input
                        == slot.bchSignatureAuthorizationRequest.input,
                      publication.submission.authorizationToken.verify(
                        purpose: .bchSignature,
                        binding: slot.componentAuthorizationRequest.input
                            .spentIdentifier,
                        using: material.manifest.core
                            .bchSignatureAuthorizationVerificationKey
                      ) else {
                    throw .bchSignatureMismatch(slot: slot.slot)
                }
                entries.append(
                    .init(
                        slot: slot.slot,
                        recipientEventIdentity: slot.recipientEventIdentity,
                        senderPrivateKey: slot.bchSignatureEnvelopePrivateKey,
                        submission: publication.submission
                    )
                )
            }

            self.context = context
            materialBinding = .init(material: material)
            transcriptRoot = transcript.transcriptRoot
            self.entries = entries.sorted {
                $0.recipientEventIdentity.lexicographicallyPrecedes(
                    $1.recipientEventIdentity
                )
            }
        }

        private struct Outpoint: Hashable {
            let transactionHash: [UInt8]
            let outputIndex: UInt32
        }

        private static func inputIndexByOutpoint(
            in transcript: OpalFusion.Mosaic.OpalV0
                .UnsignedTransactionTranscript
        ) -> [Outpoint: Int] {
            Dictionary(
                uniqueKeysWithValues: transcript.transaction.inputs
                    .enumerated().map { index, input in
                        (
                            Outpoint(
                                transactionHash: Array(
                                    input.previousTransactionHashLittleEndian
                                        .reversed()
                                ),
                                outputIndex: input.previousOutputIndex
                            ),
                            index
                        )
                    }
            )
        }
    }
}
