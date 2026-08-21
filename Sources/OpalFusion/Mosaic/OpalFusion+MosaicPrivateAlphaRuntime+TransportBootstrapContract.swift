// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapContract.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    enum TransportBootstrapContract {
        static let identifier =
            "nostr-tor/0-opal-mosaic-private-alpha-bootstrap.1"
        static let nostrSelector =
            "nostr-tor/0-opal-mosaic-boot.1"
        static let domainPrefix =
            "Mosaic/private-alpha-transport-bootstrap.1/"
        static let anonymousMailboxCount = OpalFusion.Mosaic
            .OpalMainnetAlpha.componentCountPerContributor
        static let maximumCanonicalDocumentByteCount = OpalFusion.Mosaic
            .PaddedEnvelopeCodec.maximumPayloadByteCount
        static let maximumAggregateCanonicalDocumentByteCount = 65_536

        enum DocumentKind: UInt8 {
            case authorizationKey = 0
            case controlMailboxClaim = 1
            case blindResponseSet = 2
            case anonymousMailboxRegistration = 3
            case anonymousMailboxAssignment = 4
            case anonymousMailboxRegistrationSet = 5
            case registrationSetAcknowledgement = 6
        }

        struct Context {
            let roundIdentifier: Data
            let relaySetDigest: Data
            let phaseStartUnixSeconds: UInt64
            let expiryUnixSeconds: UInt64
            let preManifestEventIdentities: [Data]
            let controlIdentities: [Data]
            let conductorControlIdentity: Data
            let contributorControlIdentities: [Data]

            init(proof: PrivateDeploymentProof) {
                roundIdentifier = proof.roundIdentifier
                relaySetDigest = proof.relaySetDigest
                phaseStartUnixSeconds = proof.phaseStartUnixSeconds
                expiryUnixSeconds =
                    proof.walletReservationDeadlineUnixSeconds
                preManifestEventIdentities =
                    proof.preManifestEventIdentities
                controlIdentities = proof.controlIdentities.sorted {
                    $0.lexicographicallyPrecedes($1)
                }
                conductorControlIdentity = proof.conductorControlIdentity
                contributorControlIdentities =
                    proof.contributorControlIdentities.sorted {
                        $0.lexicographicallyPrecedes($1)
                    }
            }
        }

        static func writeCommon(
            to encoder: inout OpalFusion.Mosaic.CanonicalEncoder,
            context: Context,
            kind: DocumentKind
        ) throws {
            try encoder.writeText(identifier)
            try encoder.writeText(
                OpalFusion.Mosaic.OpalMainnetAlpha
                    .PrivateDeploymentNostrSelector.identifier
            )
            try encoder.writeText(
                OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue
            )
            try encoder.writeText(
                OpalFusion.Mosaic.Profile.opalMainnetAlpha
                    .transportProfile.rawValue
            )
            try encoder.writeFixedBytes(
                OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash,
                byteCount: 32
            )
            try encoder.writeFixedBytes(
                Array(context.roundIdentifier),
                byteCount: 32
            )
            try encoder.writeFixedBytes(
                Array(context.relaySetDigest),
                byteCount: 32
            )
            encoder.writeUInt64(context.phaseStartUnixSeconds)
            encoder.writeUInt64(context.expiryUnixSeconds)
            encoder.writeUInt8(kind.rawValue)
        }

        static func readCommon(
            from decoder: inout OpalFusion.Mosaic.CanonicalDecoder,
            context: Context,
            expectedKind: DocumentKind
        ) throws {
            guard try decoder.readText() == identifier,
                  try decoder.readText() == OpalFusion.Mosaic
                    .OpalMainnetAlpha.PrivateDeploymentNostrSelector.identifier,
                  try decoder.readText() == OpalFusion.Mosaic.Profile
                    .opalMainnetAlpha.rawValue,
                  try decoder.readText() == OpalFusion.Mosaic.Profile
                    .opalMainnetAlpha.transportProfile.rawValue,
                  try decoder.readFixedBytes(byteCount: 32)
                    == OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash,
                  Data(try decoder.readFixedBytes(byteCount: 32))
                    == context.roundIdentifier,
                  Data(try decoder.readFixedBytes(byteCount: 32))
                    == context.relaySetDigest,
                  try decoder.readUInt64() == context.phaseStartUnixSeconds,
                  try decoder.readUInt64() == context.expiryUnixSeconds,
                  try decoder.readUInt8() == expectedKind.rawValue else {
                throw TransportBootstrapFailure.invalidBinding
            }
        }

        static func validateCurrentTime(
            _ currentUnixSeconds: UInt64?,
            context: Context
        ) throws {
            guard let currentUnixSeconds else { return }
            guard currentUnixSeconds >= context.phaseStartUnixSeconds else {
                throw TransportBootstrapFailure.invalidTimestamp
            }
            guard currentUnixSeconds <= context.expiryUnixSeconds else {
                throw TransportBootstrapFailure.expired
            }
        }

        static func validateDocumentSize(_ document: Data) throws {
            guard !document.isEmpty,
                  document.count <= maximumCanonicalDocumentByteCount else {
                throw TransportBootstrapFailure.invalidCanonicalDocument
            }
        }

        static func validateAggregateDocumentSize(_ document: Data) throws {
            guard !document.isEmpty,
                  document.count
                    <= maximumAggregateCanonicalDocumentByteCount else {
                throw TransportBootstrapFailure.invalidCanonicalDocument
            }
        }

        static func validateEventIdentity(
            _ identity: Data,
            excluding excluded: Set<Data>
        ) throws {
            guard identity.count == 32,
                  (try? OpalCrypto.Signature.BIP340.VerificationKey(
                      rawRepresentation: identity
                  )) != nil else {
                throw TransportBootstrapFailure.invalidRecipient
            }
            guard !excluded.contains(identity) else {
                throw TransportBootstrapFailure.identityReuse
            }
        }

        static func verifySignature(
            _ signature: Data,
            body: Data,
            suffix: String,
            signerIdentity: Data
        ) throws {
            guard let verificationKey = try? OpalCrypto.Signature.BIP340
                    .VerificationKey(rawRepresentation: signerIdentity),
                  OpalFusion.Mosaic.OpalMainnetAlpha
                    .PrivateDeploymentSignatureValidation.verify(
                        signatureBytes: Array(signature),
                        digestBytes: Array(hash(suffix: suffix, body: body)),
                        using: verificationKey
                    ) else {
                throw TransportBootstrapFailure.invalidSignature
            }
        }

        static func sign(
            body: Data,
            suffix: String,
            using signingKey: OpalCrypto.Secp256k1.SigningKey,
            auxiliaryRandomness:
                OpalCrypto.Signature.BIP340.AuxiliaryRandomness
        ) throws -> Data {
            try signingKey.signBIP340(
                digest: signatureDigest(suffix: suffix, body: body),
                auxiliaryRandomness: auxiliaryRandomness
            ).rawRepresentation
        }

        static func hash(suffix: String, body: Data) -> Data {
            OpalCrypto.Hashing.sha256(
                Data((domainPrefix + suffix).utf8) + body
            )
        }

        static func signatureDigest(
            suffix: String,
            body: Data
        ) throws -> OpalCrypto.Signature.Digest {
            try .init(rawRepresentation: hash(suffix: suffix, body: body))
        }

        static func mailboxBundleCommitment(
            recipientEventIdentities: [Data]
        ) throws -> Data {
            guard recipientEventIdentities.count == anonymousMailboxCount,
                  Set(recipientEventIdentities).count
                    == recipientEventIdentities.count else {
                throw TransportBootstrapFailure
                    .invalidAnonymousMailboxCount
            }
            var encoder = OpalFusion.Mosaic.CanonicalEncoder()
            try encoder.writeText(identifier)
            try encoder.writeVector(recipientEventIdentities) {
                encoder,
                identity in
                try encoder.writeFixedBytes(Array(identity), byteCount: 32)
            }
            return hash(
                suffix: "anonymous-mailbox-bundle",
                body: Data(encoder.encodedBytes)
            )
        }
    }
}
#endif
