// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapRegistrationSetAcknowledgement.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// One roster member's signature over only the common registration-set digest.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapRegistrationSetAcknowledgement:
        Sendable,
        Equatable
    {
        @_spi(MosaicPrivateAlpha) public let controlIdentity: Data
        @_spi(MosaicPrivateAlpha) public let registrationSetDigest: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        let signature: Data

        init(
            controlIdentity: Data,
            registrationSetDigest: Data,
            canonicalDocument: Data,
            signature: Data
        ) {
            self.controlIdentity = controlIdentity
            self.registrationSetDigest = registrationSetDigest
            self.canonicalDocument = canonicalDocument
            self.signature = signature
        }
    }

    /// The complete, exact-roster acknowledgement barrier for one registration set.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapRegistrationSetAcknowledgementSet:
        Sendable,
        Equatable
    {
        @_spi(MosaicPrivateAlpha) public let registrationSetDigest: Data
        @_spi(MosaicPrivateAlpha) public let acknowledgements:
            [TransportBootstrapRegistrationSetAcknowledgement]
        @_spi(MosaicPrivateAlpha) public let digest: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        init(
            registrationSetDigest: Data,
            acknowledgements:
                [TransportBootstrapRegistrationSetAcknowledgement],
            digest: Data,
            canonicalDocument: Data
        ) {
            self.registrationSetDigest = registrationSetDigest
            self.acknowledgements = acknowledgements
            self.digest = digest
            self.canonicalDocument = canonicalDocument
        }
    }

    @_spi(MosaicPrivateAlpha)
    public static func makeTransportBootstrapRegistrationSetAcknowledgement(
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        registrationSet: TransportBootstrapAnonymousMailboxRegistrationSet,
        controlSigningKey: OpalCrypto.Secp256k1.SigningKey,
        localAnonymousMailboxAssignment:
            TransportBootstrapAnonymousMailboxAssignment?,
        auxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapRegistrationSetAcknowledgement {
        let context = TransportBootstrapContract.Context(proof: proof)
        let set = try loadTransportBootstrapAnonymousMailboxRegistrationSet(
            from: registrationSet.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: currentUnixSeconds
        )
        let controlIdentity = controlSigningKey.bip340VerificationKey
            .rawRepresentation
        guard context.controlIdentities.contains(controlIdentity) else {
            throw TransportBootstrapFailure.invalidSigner
        }
        let isContributor = context.contributorControlIdentities.contains(
            controlIdentity
        )
        guard isContributor
                == (localAnonymousMailboxAssignment != nil) else {
            throw TransportBootstrapFailure.invalidAcknowledgementSet
        }
        if let assignment = localAnonymousMailboxAssignment {
            guard assignment.roundIdentifier == context.roundIdentifier,
                  assignment.relaySetDigest == context.relaySetDigest,
                  set.mailboxBundleCommitments.contains(
                assignment.mailboxBundleCommitment
            ) else {
                throw TransportBootstrapFailure.invalidRegistrationSet
            }
        }
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try TransportBootstrapContract.writeCommon(
            to: &encoder,
            context: context,
            kind: .registrationSetAcknowledgement
        )
        try encoder.writeFixedBytes(Array(set.digest), byteCount: 32)
        try encoder.writeFixedBytes(Array(controlIdentity), byteCount: 32)
        let body = Data(encoder.encodedBytes)
        let signature = try TransportBootstrapContract.sign(
            body: body,
            suffix: "registration-set-acknowledgement",
            using: controlSigningKey,
            auxiliaryRandomness: auxiliaryRandomness
        )
        var canonical = body
        canonical.append(signature)
        return try loadTransportBootstrapRegistrationSetAcknowledgement(
            from: canonical,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            registrationSet: set,
            currentUnixSeconds: currentUnixSeconds
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func loadTransportBootstrapRegistrationSetAcknowledgement(
        from canonicalDocument: Data,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        registrationSet: TransportBootstrapAnonymousMailboxRegistrationSet,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapRegistrationSetAcknowledgement {
        let context = TransportBootstrapContract.Context(proof: proof)
        let set = try loadTransportBootstrapAnonymousMailboxRegistrationSet(
            from: registrationSet.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: currentUnixSeconds
        )
        try TransportBootstrapContract.validateDocumentSize(canonicalDocument)
        let decoded: (
            body: Data,
            setDigest: Data,
            controlIdentity: Data,
            signature: Data
        )
        do {
            decoded = try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: Array(canonicalDocument)
            ) { decoder in
                try TransportBootstrapContract.readCommon(
                    from: &decoder,
                    context: context,
                    expectedKind: .registrationSetAcknowledgement
                )
                let bodyByteCount = canonicalDocument.count - 64
                guard bodyByteCount > 0 else {
                    throw TransportBootstrapFailure
                        .invalidCanonicalDocument
                }
                return (
                    canonicalDocument.prefix(bodyByteCount),
                    Data(try decoder.readFixedBytes(byteCount: 32)),
                    Data(try decoder.readFixedBytes(byteCount: 32)),
                    Data(try decoder.readFixedBytes(byteCount: 64))
                )
            }
        } catch let failure as TransportBootstrapFailure {
            throw failure
        } catch {
            throw TransportBootstrapFailure.invalidCanonicalDocument
        }
        guard decoded.setDigest == set.digest,
              context.controlIdentities.contains(
                  decoded.controlIdentity
              ) else {
            throw TransportBootstrapFailure.invalidAcknowledgementSet
        }
        try TransportBootstrapContract.verifySignature(
            decoded.signature,
            body: decoded.body,
            suffix: "registration-set-acknowledgement",
            signerIdentity: decoded.controlIdentity
        )
        try TransportBootstrapContract.validateCurrentTime(
            currentUnixSeconds,
            context: context
        )
        return .init(
            controlIdentity: decoded.controlIdentity,
            registrationSetDigest: decoded.setDigest,
            canonicalDocument: canonicalDocument,
            signature: decoded.signature
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func makeTransportBootstrapRegistrationSetAcknowledgementSet(
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        registrationSet: TransportBootstrapAnonymousMailboxRegistrationSet,
        acknowledgements:
            [TransportBootstrapRegistrationSetAcknowledgement],
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapRegistrationSetAcknowledgementSet {
        let context = TransportBootstrapContract.Context(proof: proof)
        let set = try loadTransportBootstrapAnonymousMailboxRegistrationSet(
            from: registrationSet.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: currentUnixSeconds
        )
        let normalized = try acknowledgements.map {
            try loadTransportBootstrapRegistrationSetAcknowledgement(
                from: $0.canonicalDocument,
                proof: proof,
                authorizationKey: authorizationKey,
                claimSet: claimSet,
                responseSet: responseSet,
                registrationSet: set,
                currentUnixSeconds: currentUnixSeconds
            )
        }.sorted {
            $0.controlIdentity.lexicographicallyPrecedes(
                $1.controlIdentity
            )
        }
        guard normalized.map(\.controlIdentity)
                == context.controlIdentities,
              Set(normalized.map(\.controlIdentity)).count
                == context.controlIdentities.count else {
            throw TransportBootstrapFailure.invalidAcknowledgementSet
        }
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeText(
            TransportBootstrapContract.identifier + "/acknowledgement-set"
        )
        try encoder.writeFixedBytes(
            Array(context.roundIdentifier),
            byteCount: 32
        )
        try encoder.writeFixedBytes(
            Array(context.relaySetDigest),
            byteCount: 32
        )
        try encoder.writeFixedBytes(Array(set.digest), byteCount: 32)
        try encoder.writeVector(normalized) { encoder, acknowledgement in
            try encoder.writeBytes(
                Array(acknowledgement.canonicalDocument)
            )
        }
        let canonical = Data(encoder.encodedBytes)
        try TransportBootstrapContract.validateDocumentSize(canonical)
        return .init(
            registrationSetDigest: set.digest,
            acknowledgements: normalized,
            digest: TransportBootstrapContract.hash(
                suffix: "registration-set-acknowledgement-set",
                body: canonical
            ),
            canonicalDocument: canonical
        )
    }

    @_spi(MosaicPrivateAlpha)
    public static func loadTransportBootstrapRegistrationSetAcknowledgementSet(
        from canonicalDocument: Data,
        proof: PrivateDeploymentProof,
        authorizationKey: TransportBootstrapAuthorizationKeyDocument,
        claimSet: TransportBootstrapControlMailboxClaimSet,
        responseSet: TransportBootstrapBlindResponseSet,
        registrationSet: TransportBootstrapAnonymousMailboxRegistrationSet,
        currentUnixSeconds: UInt64
    ) throws -> TransportBootstrapRegistrationSetAcknowledgementSet {
        let context = TransportBootstrapContract.Context(proof: proof)
        let set = try loadTransportBootstrapAnonymousMailboxRegistrationSet(
            from: registrationSet.canonicalDocument,
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            currentUnixSeconds: currentUnixSeconds
        )
        try TransportBootstrapContract.validateDocumentSize(canonicalDocument)
        let acknowledgements: [TransportBootstrapRegistrationSetAcknowledgement]
        do {
            acknowledgements = try OpalFusion.Mosaic.CanonicalDecoder.decode(
                from: Array(canonicalDocument)
            ) { decoder in
                guard try decoder.readText()
                        == TransportBootstrapContract.identifier
                            + "/acknowledgement-set",
                      Data(try decoder.readFixedBytes(byteCount: 32))
                        == context.roundIdentifier,
                      Data(try decoder.readFixedBytes(byteCount: 32))
                        == context.relaySetDigest,
                      Data(try decoder.readFixedBytes(byteCount: 32))
                        == set.digest else {
                    throw TransportBootstrapFailure.invalidBinding
                }
                return try decoder.readVector(
                    maximumCount: context.controlIdentities.count
                ) { decoder in
                    try loadTransportBootstrapRegistrationSetAcknowledgement(
                        from: Data(try decoder.readBytes(
                            maximumByteCount: TransportBootstrapContract
                                .maximumCanonicalDocumentByteCount
                        )),
                        proof: proof,
                        authorizationKey: authorizationKey,
                        claimSet: claimSet,
                        responseSet: responseSet,
                        registrationSet: set,
                        currentUnixSeconds: currentUnixSeconds
                    )
                }
            }
        } catch let failure as TransportBootstrapFailure {
            throw failure
        } catch {
            throw TransportBootstrapFailure.invalidCanonicalDocument
        }
        let result = try makeTransportBootstrapRegistrationSetAcknowledgementSet(
            proof: proof,
            authorizationKey: authorizationKey,
            claimSet: claimSet,
            responseSet: responseSet,
            registrationSet: set,
            acknowledgements: acknowledgements,
            currentUnixSeconds: currentUnixSeconds
        )
        guard result.canonicalDocument == canonicalDocument else {
            throw TransportBootstrapFailure.invalidCanonicalDocument
        }
        return result
    }
}
#endif
