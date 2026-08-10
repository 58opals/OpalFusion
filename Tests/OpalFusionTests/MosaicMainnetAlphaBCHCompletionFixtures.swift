// MosaicMainnetAlphaBCHCompletionFixtures.swift

import Foundation
import OpalCrypto
@testable import OpalFusion

enum MosaicMainnetAlphaBCHCompletionFixtures {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha

    enum FixtureError: Error {
        case missingInput
    }

    struct Prepared {
        let transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
        let acceptedInput: OpalFusion.Mosaic.OpalV0.Component
        let previousOutputs: Alpha.PreviousOutputResolver.Validation
        let submission: Alpha.BCHSignatureSubmission
        let signatureSet: Alpha.BCHSignatureSet
        let payload: Alpha.CompleteTransactionPayload
    }

    struct PreviousOutputSource: OpalFusion.Host.MosaicPreviousOutputSource {
        let lockingScript: [UInt8]

        func resolvePreviousOutputs(
            for requests: [OpalFusion.Host.MosaicPreviousOutputRequest]
        ) async throws -> [OpalFusion.Host.MosaicPreviousOutput] {
            try requests.map { request in
                try .init(
                    transactionHashBytes: request.transactionHashBytes,
                    outputIndex: request.outputIndex,
                    amountSatoshis: request.expectedAmountSatoshis,
                    lockingScriptBytes: lockingScript,
                    tokenState: .absent
                )
            }
        }
    }

    static func prepare(
        componentSaltOffset: Int = 0
    ) async throws -> Prepared {
        let election = try MosaicMainnetAlphaFixtures.makeElection()
        let manifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: election,
            verificationKey: MosaicMainnetAlphaFixtures.rsaVerificationKey()
        )
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures
            .prepare(
                roster: election.result.roster,
                manifest: manifest.binding,
                profile: .opalMainnetAlpha,
                componentSaltOffset: componentSaltOffset
            )
        let acceptedInput = try preparation.componentSet.components.first {
            if case .input = $0.payload {
                return true
            }
            return false
        }.unwrap()
        let signingKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([11])
        )
        let publicKey = [UInt8](signingKey.publicKey.compressedRepresentation)
        let validLockingScript = [UInt8(0x76), 0xa9, 0x14]
            + OpalFusion.Execution.ProtocolPrimitives.hash160(publicKey)
            + [0x88, 0xac]
        let previousOutputs = try await resolve(
            transcript: preparation.transcript,
            lockingScript: validLockingScript
        )
        let spentInput = try previousOutputs.spentInputs.first.unwrap()
        let signatureHash = try preparation.transcript.transaction.signatureHash(
            forInputAt: 0,
            lockingScript: validLockingScript,
            amountSatoshis: spentInput.amountSatoshis,
            sighashType: 0x41
        )
        let signature = try signingKey.signSchnorr(
            digest: .init(rawRepresentation: Data(signatureHash))
        )
        let entry = try Alpha.BCHSignatureEntry(
            inputIndex: 0,
            signature: [UInt8](signature.rawRepresentation),
            publicKey: publicKey
        )
        let token = try MosaicMainnetAlphaFixtures.makeAuthorizationToken(
            purpose: .bchSignature,
            binding: MosaicUnsignedTransactionTranscriptFixtures.indexedDigest(7_000),
            roundIdentifier: manifest.core.roundIdentifier
        )
        let submission = try Alpha.BCHSignatureSubmission(
            transcriptRoot: preparation.transcript.transcriptRoot.validatedBytes,
            authorizationToken: token,
            entry: entry
        )
        let signatureSet = try Alpha.BCHSignatureSet(
            roundIdentifier: manifest.core.roundIdentifier,
            transcriptRoot: preparation.transcript.transcriptRoot.validatedBytes,
            entries: [entry],
            expectedInputCount: 1
        )
        let completeTransaction = try Alpha.CompleteTransactionAssembler.assemble(
            transcript: preparation.transcript,
            signatureSet: signatureSet,
            spentInputs: previousOutputs.spentInputs
        )
        let payload = try Alpha.CompleteTransactionPayload(
            roundIdentifier: manifest.core.roundIdentifier,
            transcriptRoot: preparation.transcript.transcriptRoot.validatedBytes,
            completeTransaction: completeTransaction
        )
        return .init(
            transcript: preparation.transcript,
            acceptedInput: acceptedInput,
            previousOutputs: previousOutputs,
            submission: submission,
            signatureSet: signatureSet,
            payload: payload
        )
    }

    static func resolve(
        transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript,
        lockingScript: [UInt8]
    ) async throws -> Alpha.PreviousOutputResolver.Validation {
        try await Alpha.PreviousOutputResolver(
            source: PreviousOutputSource(lockingScript: lockingScript)
        ).resolve(for: transcript)
    }
}

private extension Optional {
    func unwrap() throws -> Wrapped {
        guard let self else {
            throw MosaicMainnetAlphaBCHCompletionFixtures.FixtureError.missingInput
        }
        return self
    }
}
