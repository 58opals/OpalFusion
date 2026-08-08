// OpalFusion+Mosaic+Attempt+TranscriptAcknowledgement.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.Attempt {
    /// The fixed-width transcript root acknowledged before Bitcoin Cash signing.
    struct TranscriptRoot: Sendable, Hashable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidByteCount(actual: Int)
        }

        let validatedBytes: [UInt8]

        init(validating bytes: [UInt8]) throws(ValidationError) {
            guard bytes.count == OpalFusion.Mosaic.OpalV0.digestByteCount else {
                throw .invalidByteCount(actual: bytes.count)
            }
            self.validatedBytes = Array(bytes)
        }
    }

    /// One unverified contributor signature over a pre-sign acknowledgement payload.
    struct TranscriptAcknowledgement: Sendable, Equatable {
        let contributor: ControlIdentity
        let roundIdentifier: [UInt8]
        let transcriptRoot: [UInt8]
        let rawRepresentation: [UInt8]

        init(
            contributor: ControlIdentity,
            roundIdentifier: [UInt8],
            transcriptRoot: [UInt8],
            rawRepresentation: [UInt8]
        ) {
            self.contributor = contributor
            self.roundIdentifier = Array(roundIdentifier)
            self.transcriptRoot = Array(transcriptRoot)
            self.rawRepresentation = Array(rawRepresentation)
        }
    }

    /// Proof that one control identity signed a canonical round-and-transcript acknowledgement.
    struct TranscriptAcknowledgementValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidControlIdentityByteCount(actual: Int)
            case invalidControlIdentity
            case invalidRoundIdentifierByteCount(actual: Int)
            case invalidTranscriptRootByteCount(actual: Int)
            case invalidSignatureByteCount(actual: Int)
            case invalidSignature
            case signatureVerificationFailed
        }

        let contributor: ControlIdentity
        let profile: OpalFusion.Mosaic.Profile
        let roundIdentifier: [UInt8]
        let transcriptRoot: TranscriptRoot

        init(
            validating acknowledgement: TranscriptAcknowledgement,
            profile: OpalFusion.Mosaic.Profile
        ) throws(ValidationError) {
            guard acknowledgement.contributor.validatedBytes.count == 32 else {
                throw .invalidControlIdentityByteCount(
                    actual: acknowledgement.contributor.validatedBytes.count
                )
            }
            guard acknowledgement.roundIdentifier.count
                == OpalFusion.Mosaic.OpalV0.digestByteCount else {
                throw .invalidRoundIdentifierByteCount(
                    actual: acknowledgement.roundIdentifier.count
                )
            }
            guard acknowledgement.transcriptRoot.count
                == OpalFusion.Mosaic.OpalV0.digestByteCount else {
                throw .invalidTranscriptRootByteCount(
                    actual: acknowledgement.transcriptRoot.count
                )
            }
            guard acknowledgement.rawRepresentation.count == 64 else {
                throw .invalidSignatureByteCount(
                    actual: acknowledgement.rawRepresentation.count
                )
            }

            let verificationKey: OpalCrypto.Signature.BIP340.VerificationKey
            do {
                verificationKey = try .init(
                    rawRepresentation: Data(acknowledgement.contributor.validatedBytes)
                )
            } catch {
                throw .invalidControlIdentity
            }

            let parsedSignature: OpalCrypto.Signature.BIP340
            do {
                parsedSignature = try .init(
                    rawRepresentation: Data(acknowledgement.rawRepresentation)
                )
            } catch {
                throw .invalidSignature
            }

            let digest = Self.signatureDigest(
                profile: profile,
                roundIdentifier: acknowledgement.roundIdentifier,
                transcriptRoot: acknowledgement.transcriptRoot
            )
            guard parsedSignature.verify(
                digest: digest,
                verificationKey: verificationKey
            ) else {
                throw .signatureVerificationFailed
            }

            let transcriptRoot: TranscriptRoot
            do {
                transcriptRoot = try .init(validating: acknowledgement.transcriptRoot)
            } catch {
                preconditionFailure(
                    "Transcript acknowledgement width was validated before constructing its root."
                )
            }

            self.contributor = acknowledgement.contributor
            self.profile = profile
            self.roundIdentifier = acknowledgement.roundIdentifier
            self.transcriptRoot = transcriptRoot
        }

        static func signatureDigest(
            profile: OpalFusion.Mosaic.Profile,
            roundIdentifier: [UInt8],
            transcriptRoot: [UInt8]
        ) -> OpalCrypto.Signature.Digest {
            let payload: OpalFusion.Mosaic.OpalV0.PreSignAcknowledgementPayload
            let canonicalBody: [UInt8]
            do {
                payload = try .init(
                    roundIdentifier: roundIdentifier,
                    transcriptRoot: transcriptRoot
                )
                canonicalBody = try OpalFusion.Mosaic.OpalV0.CanonicalWireCodec
                    .encodePreSignAcknowledgement(payload)
            } catch {
                preconditionFailure(
                    "Pre-sign digest construction requires canonical 32-byte fields."
                )
            }
            let digestBytes = OpalCrypto.Hashing.sha256(
                Data("\(profile.rawValue)/pre-sign-ack".utf8) + Data(canonicalBody)
            )
            do {
                return try .init(rawRepresentation: digestBytes)
            } catch {
                preconditionFailure("SHA-256 always produces a valid BIP340 digest.")
            }
        }
    }
}
