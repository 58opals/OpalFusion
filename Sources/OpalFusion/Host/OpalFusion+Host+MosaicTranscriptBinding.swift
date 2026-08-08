// OpalFusion+Host+MosaicTranscriptBinding.swift

import Foundation
import OpalCrypto

public extension OpalFusion.Host {
    /// Recomputable Opal-v0 transcript material that binds a signing request to exact transaction bytes.
    ///
    /// Construction proves that the supplied transcript root matches these digests. The attempt reducer
    /// remains responsible for requiring every contributor to acknowledge that root before this value is
    /// used. Other Mosaic profiles fail closed until their transcript documents are frozen.
    struct MosaicTranscriptBinding: Sendable, Equatable {
        public let profile: OpalFusion.Mosaic.Profile
        public let manifestDigest: [UInt8]
        public let commitmentSetDigest: [UInt8]
        public let componentSetDigest: [UInt8]
        public let unsignedTransactionDigest: [UInt8]
        public let transcriptRoot: [UInt8]

        public init(
            profile: OpalFusion.Mosaic.Profile,
            manifestDigest: [UInt8],
            commitmentSetDigest: [UInt8],
            componentSetDigest: [UInt8],
            unsignedTransactionBytes: [UInt8],
            acknowledgedTranscriptRoot: [UInt8]
        ) throws {
            guard profile == .opalV0 else {
                throw MosaicHostContractError.unsupportedProfile(profile)
            }
            try Self.validateDigestLengths(
                manifestDigest: manifestDigest,
                commitmentSetDigest: commitmentSetDigest,
                componentSetDigest: componentSetDigest
            )
            guard !unsignedTransactionBytes.isEmpty else {
                throw MosaicHostContractError.emptyUnsignedTransaction
            }
            guard UInt32(exactly: unsignedTransactionBytes.count) != nil else {
                throw MosaicHostContractError.unsignedTransactionTooLarge(
                    actual: unsignedTransactionBytes.count
                )
            }
            guard acknowledgedTranscriptRoot.count == 32 else {
                throw MosaicHostContractError.invalidTranscriptRootLength(
                    actual: acknowledgedTranscriptRoot.count
                )
            }

            let unsignedTransactionDigest = Self.unsignedTransactionDigest(
                profile: profile,
                unsignedTransactionBytes: unsignedTransactionBytes
            )
            let expectedRoot = Self.makeTranscriptRoot(
                profile: profile,
                manifestDigest: manifestDigest,
                commitmentSetDigest: commitmentSetDigest,
                componentSetDigest: componentSetDigest,
                unsignedTransactionDigest: unsignedTransactionDigest
            )
            guard acknowledgedTranscriptRoot == expectedRoot else {
                throw MosaicHostContractError.transcriptRootMismatch
            }

            self.profile = profile
            self.manifestDigest = Array(manifestDigest)
            self.commitmentSetDigest = Array(commitmentSetDigest)
            self.componentSetDigest = Array(componentSetDigest)
            self.unsignedTransactionDigest = unsignedTransactionDigest
            self.transcriptRoot = Array(acknowledgedTranscriptRoot)
        }

        /// Computes the Opal-v0 root contributors must acknowledge for the supplied material.
        public static func transcriptRoot(
            profile: OpalFusion.Mosaic.Profile,
            manifestDigest: [UInt8],
            commitmentSetDigest: [UInt8],
            componentSetDigest: [UInt8],
            unsignedTransactionBytes: [UInt8]
        ) throws -> [UInt8] {
            guard profile == .opalV0 else {
                throw MosaicHostContractError.unsupportedProfile(profile)
            }
            try validateDigestLengths(
                manifestDigest: manifestDigest,
                commitmentSetDigest: commitmentSetDigest,
                componentSetDigest: componentSetDigest
            )
            guard !unsignedTransactionBytes.isEmpty else {
                throw MosaicHostContractError.emptyUnsignedTransaction
            }
            guard UInt32(exactly: unsignedTransactionBytes.count) != nil else {
                throw MosaicHostContractError.unsignedTransactionTooLarge(
                    actual: unsignedTransactionBytes.count
                )
            }
            return makeTranscriptRoot(
                profile: profile,
                manifestDigest: manifestDigest,
                commitmentSetDigest: commitmentSetDigest,
                componentSetDigest: componentSetDigest,
                unsignedTransactionDigest: unsignedTransactionDigest(
                    profile: profile,
                    unsignedTransactionBytes: unsignedTransactionBytes
                )
            )
        }

        /// Checks exact transaction bytes against the digest committed by this binding.
        public func matches(unsignedTransactionBytes: [UInt8]) -> Bool {
            guard UInt32(exactly: unsignedTransactionBytes.count) != nil else {
                return false
            }
            return Self.unsignedTransactionDigest(
                profile: profile,
                unsignedTransactionBytes: unsignedTransactionBytes
            ) == unsignedTransactionDigest
        }

        private static func validateDigestLengths(
            manifestDigest: [UInt8],
            commitmentSetDigest: [UInt8],
            componentSetDigest: [UInt8]
        ) throws {
            guard manifestDigest.count == 32 else {
                throw MosaicHostContractError.invalidManifestDigestLength(
                    actual: manifestDigest.count
                )
            }
            guard commitmentSetDigest.count == 32 else {
                throw MosaicHostContractError.invalidCommitmentSetDigestLength(
                    actual: commitmentSetDigest.count
                )
            }
            guard componentSetDigest.count == 32 else {
                throw MosaicHostContractError.invalidComponentSetDigestLength(
                    actual: componentSetDigest.count
                )
            }
        }

        private static func unsignedTransactionDigest(
            profile: OpalFusion.Mosaic.Profile,
            unsignedTransactionBytes: [UInt8]
        ) -> [UInt8] {
            hash(
                domain: "\(profile.rawValue)/unsigned-transaction",
                fields: [unsignedTransactionBytes]
            )
        }

        private static func makeTranscriptRoot(
            profile: OpalFusion.Mosaic.Profile,
            manifestDigest: [UInt8],
            commitmentSetDigest: [UInt8],
            componentSetDigest: [UInt8],
            unsignedTransactionDigest: [UInt8]
        ) -> [UInt8] {
            hash(
                domain: "\(profile.rawValue)/transcript",
                fields: [
                    manifestDigest,
                    commitmentSetDigest,
                    componentSetDigest,
                    unsignedTransactionDigest
                ]
            )
        }

        private static func hash(
            domain: String,
            fields: [[UInt8]]
        ) -> [UInt8] {
            var preimage = Data(domain.utf8)
            for field in fields {
                appendLengthPrefixed(field, to: &preimage)
            }
            return [UInt8](OpalCrypto.Hashing.sha256(preimage))
        }

        private static func appendLengthPrefixed(
            _ bytes: [UInt8],
            to destination: inout Data
        ) {
            let count = UInt32(bytes.count)
            destination.append(UInt8(truncatingIfNeeded: count >> 24))
            destination.append(UInt8(truncatingIfNeeded: count >> 16))
            destination.append(UInt8(truncatingIfNeeded: count >> 8))
            destination.append(UInt8(truncatingIfNeeded: count))
            destination.append(contentsOf: bytes)
        }
    }
}
