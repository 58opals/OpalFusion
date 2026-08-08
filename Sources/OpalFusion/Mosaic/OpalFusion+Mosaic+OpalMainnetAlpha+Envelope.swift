// OpalFusion+Mosaic+OpalMainnetAlpha+Envelope.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    enum ControlPayloadType: UInt16, CaseIterable, Sendable, Equatable {
        case aggregateReservation = 0x0001
        case aggregateFragment = 0x0002
        case preSignAcknowledgement = 0x0003
    }

    struct ControlEnvelope: Sendable, Equatable {
        let roundIdentifier: [UInt8]
        let phase: OpalFusion.Mosaic.Attempt.Phase
        let senderControlIdentity: OpalFusion.Mosaic.Attempt.ControlIdentity
        let senderEventIdentity: [UInt8]
        let sequence: UInt64
        let payloadType: ControlPayloadType
        let payloadDigest: [UInt8]
        let expiryUnixSeconds: UInt64
        let controlSignature: [UInt8]
        let payload: [UInt8]
        let messageDigest: [UInt8]

        init(
            roundIdentifier: [UInt8],
            phase: OpalFusion.Mosaic.Attempt.Phase,
            senderControlIdentity: OpalFusion.Mosaic.Attempt.ControlIdentity,
            senderEventIdentity: [UInt8],
            sequence: UInt64,
            payloadType: ControlPayloadType,
            expiryUnixSeconds: UInt64,
            controlSignature: [UInt8],
            payload: [UInt8]
        ) throws {
            try RoleSeedValidator.validateFixed(
                roundIdentifier,
                field: .roundIdentifier
            )
            try RoleSeedValidator.validateFixed(
                senderControlIdentity.validatedBytes,
                field: .controlIdentity
            )
            try RoleSeedValidator.validateFixed(
                senderEventIdentity,
                field: .senderEventIdentity
            )
            guard senderControlIdentity.validatedBytes != senderEventIdentity else {
                throw ContractError.reusedControlAndEventIdentity
            }

            let controlVerificationKey: OpalCrypto.Signature.BIP340.VerificationKey
            do {
                controlVerificationKey = try .init(
                    rawRepresentation: Data(senderControlIdentity.validatedBytes)
                )
            } catch {
                throw ContractError.invalidControlIdentity
            }
            do {
                _ = try OpalCrypto.Signature.BIP340.VerificationKey(
                    rawRepresentation: Data(senderEventIdentity)
                )
            } catch {
                throw ContractError.invalidEventIdentity
            }
            guard controlSignature.count == 64 else {
                throw ContractError.invalidFixedByteCount(
                    field: .controlSignature,
                    expected: 64,
                    actual: controlSignature.count
                )
            }
            guard payload.count <= OpalFusion.Mosaic.OpalMainnetAlpha
                .maximumControlPayloadByteCount else {
                throw ContractError.payloadTooLarge(
                    maximum: OpalFusion.Mosaic.OpalMainnetAlpha
                        .maximumControlPayloadByteCount,
                    actual: payload.count
                )
            }

            let payloadDigest = Self.payloadDigest(
                payloadType: payloadType,
                payload: payload
            )
            let messageDigest = try Self.messageDigest(
                roundIdentifier: roundIdentifier,
                phase: phase,
                senderControlIdentity: senderControlIdentity,
                senderEventIdentity: senderEventIdentity,
                sequence: sequence,
                payloadType: payloadType,
                payloadDigest: payloadDigest,
                expiryUnixSeconds: expiryUnixSeconds
            )
            do {
                let signature = try OpalCrypto.Signature.BIP340(
                    rawRepresentation: Data(controlSignature)
                )
                let digest = try OpalCrypto.Signature.Digest(
                    rawRepresentation: Data(messageDigest)
                )
                guard signature.verify(
                    digest: digest,
                    verificationKey: controlVerificationKey
                ) else {
                    throw ContractError.invalidControlSignature
                }
            } catch let error as ContractError {
                throw error
            } catch {
                throw ContractError.invalidControlSignature
            }

            self.roundIdentifier = Array(roundIdentifier)
            self.phase = phase
            self.senderControlIdentity = senderControlIdentity
            self.senderEventIdentity = Array(senderEventIdentity)
            self.sequence = sequence
            self.payloadType = payloadType
            self.payloadDigest = payloadDigest
            self.expiryUnixSeconds = expiryUnixSeconds
            self.controlSignature = Array(controlSignature)
            self.payload = Array(payload)
            self.messageDigest = messageDigest

            let encodedCount = try CanonicalWireCodec.encodeControlEnvelope(self).count
            guard encodedCount <= OpalFusion.Mosaic.OpalMainnetAlpha
                .maximumControlEnvelopeByteCount else {
                throw ContractError.payloadTooLarge(
                    maximum: OpalFusion.Mosaic.OpalMainnetAlpha
                        .maximumControlPayloadByteCount,
                    actual: payload.count
                )
            }
        }

        static func signingDigest(
            roundIdentifier: [UInt8],
            phase: OpalFusion.Mosaic.Attempt.Phase,
            senderControlIdentity: OpalFusion.Mosaic.Attempt.ControlIdentity,
            senderEventIdentity: [UInt8],
            sequence: UInt64,
            payloadType: ControlPayloadType,
            expiryUnixSeconds: UInt64,
            payload: [UInt8]
        ) throws -> [UInt8] {
            try messageDigest(
                roundIdentifier: roundIdentifier,
                phase: phase,
                senderControlIdentity: senderControlIdentity,
                senderEventIdentity: senderEventIdentity,
                sequence: sequence,
                payloadType: payloadType,
                payloadDigest: payloadDigest(
                    payloadType: payloadType,
                    payload: payload
                ),
                expiryUnixSeconds: expiryUnixSeconds
            )
        }

        func validateOuterEventIdentity(_ eventIdentity: [UInt8]) throws {
            guard eventIdentity == senderEventIdentity else {
                throw ContractError.outerEventIdentityMismatch
            }
        }

        private static func payloadDigest(
            payloadType: ControlPayloadType,
            payload: [UInt8]
        ) -> [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            encoder.writeUInt16(payloadType.rawValue)
            do {
                try encoder.writeBytes(payload)
            } catch {
                preconditionFailure("A bounded control payload must fit a canonical u32 length.")
            }
            return RoleSeedValidator.hash(
                domainSuffix: "payload",
                fields: [encoder.encodedBytes]
            )
        }

        private static func messageDigest(
            roundIdentifier: [UInt8],
            phase: OpalFusion.Mosaic.Attempt.Phase,
            senderControlIdentity: OpalFusion.Mosaic.Attempt.ControlIdentity,
            senderEventIdentity: [UInt8],
            sequence: UInt64,
            payloadType: ControlPayloadType,
            payloadDigest: [UInt8],
            expiryUnixSeconds: UInt64
        ) throws -> [UInt8] {
            let body = try CanonicalWireCodec.encodeControlEnvelopeBody(
                roundIdentifier: roundIdentifier,
                phase: phase,
                senderControlIdentity: senderControlIdentity,
                senderEventIdentity: senderEventIdentity,
                sequence: sequence,
                payloadType: payloadType,
                payloadDigest: payloadDigest,
                expiryUnixSeconds: expiryUnixSeconds
            )
            return RoleSeedValidator.hash(
                domainSuffix: "message",
                fields: [body]
            )
        }
    }

    enum AnonymousPayloadType: UInt16, CaseIterable, Sendable, Equatable {
        case anonymousComponent = 0x0100
        case bchSignatureSubmission = 0x0101
    }

    struct AnonymousEnvelope: Sendable, Equatable {
        let roundIdentifier: [UInt8]
        let phase: OpalFusion.Mosaic.Attempt.Phase
        let senderCommunicationPublicKey: [UInt8]
        let recipientEventIdentity: [UInt8]
        let sequence: UInt64
        let payloadType: AnonymousPayloadType
        let payloadDigest: [UInt8]
        let expiryUnixSeconds: UInt64
        let payload: [UInt8]

        init(
            roundIdentifier: [UInt8],
            phase: OpalFusion.Mosaic.Attempt.Phase,
            senderCommunicationPublicKey: [UInt8],
            recipientEventIdentity: [UInt8],
            sequence: UInt64,
            payloadType: AnonymousPayloadType,
            expiryUnixSeconds: UInt64,
            payload: [UInt8]
        ) throws {
            try RoleSeedValidator.validateFixed(
                roundIdentifier,
                field: .roundIdentifier
            )
            guard senderCommunicationPublicKey.count
                == OpalFusion.Mosaic.OpalMainnetAlpha
                    .compressedPublicKeyByteCount else {
                throw ContractError.invalidFixedByteCount(
                    field: .bchPublicKey,
                    expected: OpalFusion.Mosaic.OpalMainnetAlpha
                        .compressedPublicKeyByteCount,
                    actual: senderCommunicationPublicKey.count
                )
            }
            do {
                _ = try OpalCrypto.Secp256k1.PublicKey(
                    rawRepresentation: Data(senderCommunicationPublicKey)
                )
            } catch {
                throw ContractError.invalidCommunicationPublicKey
            }
            do {
                _ = try OpalCrypto.Signature.BIP340.VerificationKey(
                    rawRepresentation: Data(recipientEventIdentity)
                )
            } catch {
                throw ContractError.invalidEventIdentity
            }
            guard Self.accepts(payloadType: payloadType, during: phase) else {
                throw ContractError.invalidPayloadPhase
            }
            guard payload.count <= OpalFusion.Mosaic.OpalMainnetAlpha
                .maximumAnonymousPayloadByteCount else {
                throw ContractError.payloadTooLarge(
                    maximum: OpalFusion.Mosaic.OpalMainnetAlpha
                        .maximumAnonymousPayloadByteCount,
                    actual: payload.count
                )
            }

            let payloadDigest = Self.payloadDigest(
                payloadType: payloadType,
                payload: payload
            )
            self.roundIdentifier = Array(roundIdentifier)
            self.phase = phase
            self.senderCommunicationPublicKey = Array(
                senderCommunicationPublicKey
            )
            self.recipientEventIdentity = Array(recipientEventIdentity)
            self.sequence = sequence
            self.payloadType = payloadType
            self.payloadDigest = payloadDigest
            self.expiryUnixSeconds = expiryUnixSeconds
            self.payload = Array(payload)

            let encodedCount = try CanonicalWireCodec.encodeAnonymousEnvelope(self).count
            guard encodedCount <= OpalFusion.Mosaic.OpalMainnetAlpha
                .maximumAnonymousEnvelopeByteCount else {
                throw ContractError.payloadTooLarge(
                    maximum: OpalFusion.Mosaic.OpalMainnetAlpha
                        .maximumAnonymousPayloadByteCount,
                    actual: payload.count
                )
            }
        }

        func validateOuterEventIdentity(_ eventIdentity: [UInt8]) throws {
            guard eventIdentity.count == 32,
                  Array(senderCommunicationPublicKey.dropFirst())
                    == eventIdentity else {
                throw ContractError.communicationEventIdentityMismatch
            }
        }

        private static func accepts(
            payloadType: AnonymousPayloadType,
            during phase: OpalFusion.Mosaic.Attempt.Phase
        ) -> Bool {
            switch payloadType {
            case .anonymousComponent:
                phase == .anonymousComponentSubmission
            case .bchSignatureSubmission:
                phase == .bchSigning
            }
        }

        private static func payloadDigest(
            payloadType: AnonymousPayloadType,
            payload: [UInt8]
        ) -> [UInt8] {
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            encoder.writeUInt16(payloadType.rawValue)
            do {
                try encoder.writeBytes(payload)
            } catch {
                preconditionFailure("A bounded anonymous payload must fit a canonical u32 length.")
            }
            return RoleSeedValidator.hash(
                domainSuffix: "payload",
                fields: [encoder.encodedBytes]
            )
        }
    }
}
