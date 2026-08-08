// OpalFusion+Mosaic+OpalMainnetAlpha+BCHSignature.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    struct BCHSignatureEntry: Sendable, Equatable {
        let inputIndex: UInt32
        let signature: [UInt8]
        let publicKey: [UInt8]

        init(
            inputIndex: UInt32,
            signature: [UInt8],
            publicKey: [UInt8]
        ) throws {
            guard signature.count
                == OpalFusion.Mosaic.OpalMainnetAlpha
                    .bchSchnorrSignatureByteCount else {
                throw ContractError.invalidFixedByteCount(
                    field: .bchSignature,
                    expected: OpalFusion.Mosaic.OpalMainnetAlpha
                        .bchSchnorrSignatureByteCount,
                    actual: signature.count
                )
            }
            guard publicKey.count
                == OpalFusion.Mosaic.OpalMainnetAlpha
                    .compressedPublicKeyByteCount else {
                throw ContractError.invalidFixedByteCount(
                    field: .bchPublicKey,
                    expected: OpalFusion.Mosaic.OpalMainnetAlpha
                        .compressedPublicKeyByteCount,
                    actual: publicKey.count
                )
            }
            do {
                _ = try OpalCrypto.Signature.Schnorr(
                    rawRepresentation: Data(signature)
                )
            } catch {
                throw ContractError.invalidBCHSignature
            }
            do {
                _ = try OpalCrypto.Secp256k1.PublicKey(
                    rawRepresentation: Data(publicKey)
                )
            } catch {
                throw ContractError.invalidBCHPublicKey
            }
            self.inputIndex = inputIndex
            self.signature = Array(signature)
            self.publicKey = Array(publicKey)
        }
    }

    struct BCHSignatureSubmission: Sendable, Equatable {
        let transcriptRoot: [UInt8]
        let entry: BCHSignatureEntry
        let canonicalBytes: [UInt8]
        let digest: [UInt8]

        init(
            transcriptRoot: [UInt8],
            entry: BCHSignatureEntry
        ) throws {
            try RoleSeedValidator.validateFixed(
                transcriptRoot,
                field: .transcriptRoot
            )
            let canonicalBytes = try CanonicalWireCodec
                .encodeBCHSignatureSubmission(
                    transcriptRoot: transcriptRoot,
                    entry: entry
                )
            self.transcriptRoot = Array(transcriptRoot)
            self.entry = entry
            self.canonicalBytes = canonicalBytes
            self.digest = RoleSeedValidator.hash(
                domainSuffix: "bch-signature",
                fields: [canonicalBytes]
            )
        }
    }

    struct BCHSignatureSet: Sendable, Equatable {
        let roundIdentifier: [UInt8]
        let transcriptRoot: [UInt8]
        let entries: [BCHSignatureEntry]
        let canonicalBytes: [UInt8]
        let digest: [UInt8]

        init(
            roundIdentifier: [UInt8],
            transcriptRoot: [UInt8],
            submissions: [BCHSignatureSubmission],
            expectedInputCount: Int
        ) throws {
            try RoleSeedValidator.validateFixed(
                roundIdentifier,
                field: .roundIdentifier
            )
            try RoleSeedValidator.validateFixed(
                transcriptRoot,
                field: .transcriptRoot
            )
            guard (1 ... OpalFusion.Mosaic.OpalMainnetAlpha
                .maximumTransactionInputCount).contains(expectedInputCount),
                submissions.count == expectedInputCount else {
                throw ContractError.invalidSignatureSetCount(
                    expected: expectedInputCount,
                    actual: submissions.count
                )
            }
            let sortedSubmissions = submissions.sorted {
                $0.entry.inputIndex < $1.entry.inputIndex
            }
            for (expectedIndex, submission) in sortedSubmissions.enumerated() {
                guard submission.transcriptRoot == transcriptRoot else {
                    throw ContractError.transcriptMismatch
                }
                guard submission.entry.inputIndex == UInt32(expectedIndex) else {
                    throw ContractError.invalidSignatureInputIndex(
                        expected: expectedIndex,
                        actual: Int(submission.entry.inputIndex)
                    )
                }
            }
            let entries = sortedSubmissions.map(\.entry)
            let canonicalBytes = try CanonicalWireCodec.encodeBCHSignatureSet(
                roundIdentifier: roundIdentifier,
                transcriptRoot: transcriptRoot,
                entries: entries
            )
            self.roundIdentifier = Array(roundIdentifier)
            self.transcriptRoot = Array(transcriptRoot)
            self.entries = entries
            self.canonicalBytes = canonicalBytes
            self.digest = RoleSeedValidator.hash(
                domainSuffix: "bch-signature-set",
                fields: [canonicalBytes]
            )
        }
    }
}
