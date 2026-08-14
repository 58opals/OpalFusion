// MosaicMainnetAlphaPrivateNostrMappingValidator~Terminal.swift

import Foundation
import Testing
@testable import OpalFusion

extension MosaicMainnetAlphaPrivateNostrMappingValidator {
    @Test("Round trip terminal abort and completion events")
    func roundTripTerminalAbortAndCompletionEvents() async throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let epochStart = formation.discovery.epochStart
        let manifest = try MosaicPrivateDeploymentFixtures
            .makeManifestValidation(formation: formation)
        let abortParticipant = formation.roleElection.roster.controlIdentities[0]
        let abortSigner = formation.controlCandidate(for: abortParticipant)
        let abortAuthority = try Alpha.PrivateDeploymentAbortAuthority
            .makeRoleSelectionAuthority(
                participant: abortParticipant,
                controlRoster: formation.controlRoster
            )
        let abort = try Alpha.PrivateDeploymentAbortDocument(
            discoveryEpochStartUnixSeconds: epochStart,
            phase: .roleSelection,
            context: abortAuthority.context,
            reason: .missingRequiredParticipant
        )
        let abortPayload = try Alpha.PreManifestNostrPayloadDocument.makeAbort(
            abort,
            authority: abortAuthority
        )
        #expect(abortPayload.expiryUnixSeconds == epochStart + 300)
        let abortEvent = try makeEvent(
            payload: abortPayload,
            candidate: abortSigner,
            createdAt: epochStart + 181,
            auxiliaryByte: 0xF5
        )
        #expect(
            try Alpha.PreManifestNostrCodec.decodeAbort(
                abortEvent,
                authority: abortAuthority,
                currentUnixSeconds: epochStart + 181
            ) == abort
        )

        let roundManifest = try MosaicPrivateDeploymentFixtures
            .makeRoundManifest(
                formation: formation,
                validation: manifest
            )
        let completed = try await MosaicMainnetAlphaBCHCompletionFixtures
            .prepare(manifest: roundManifest)
        let completionValidation = try Alpha
            .PrivateDeploymentCompletionValidation(
                manifest: manifest,
                roundManifest: roundManifest,
                completeTransactionValidation: completed.validation
            )
        let completion = Alpha.PrivateDeploymentCompletionDocument(
            validation: completionValidation
        )
        let completionPayload = try Alpha.PreManifestNostrPayloadDocument
            .makeCompletion(
                completion,
                validation: completionValidation
            )
        #expect(
            completionPayload.expiryUnixSeconds
                == manifest.core.deadlines.bchSigning
        )
        let conductor = formation.controlCandidate(
            for: formation.roleElection.roster.conductor
        )
        let completionTime = manifest.core.deadlines.bchSigning
        let completionEvent = try makeEvent(
            payload: completionPayload,
            candidate: conductor,
            createdAt: completionTime,
            auxiliaryByte: 0xF6
        )
        #expect(
            try Alpha.PreManifestNostrCodec.decodeCompletion(
                completionEvent,
                validation: completionValidation,
                currentUnixSeconds: completionTime
            ) == completion
        )
        let nonConductor = formation.controlCandidate(
            for: formation.roleElection.roster.contributors[0]
        )
        let falseAuthorityPayload = try Alpha
            .PreManifestNostrPayloadDocument(
                discoveryEpochStartUnixSeconds: epochStart,
                payloadKind: .completion,
                signerRole: .conductor,
                signerIdentity: nonConductor.identity,
                expiryUnixSeconds: completionPayload.expiryUnixSeconds,
                body: completionPayload.body
            )
        let falseAuthorityEvent = try makeEvent(
            payload: falseAuthorityPayload,
            candidate: nonConductor,
            createdAt: completionTime,
            auxiliaryByte: 0xFA
        )
        #expect(
            throws: Alpha.PreManifestNostrCodec.ValidationError
                .signerIdentityMismatch
        ) {
            _ = try Alpha.PreManifestNostrCodec.decodeCompletion(
                falseAuthorityEvent,
                validation: completionValidation,
                currentUnixSeconds: completionTime
            )
        }
    }

    var limits: Nostr.EventCodingLimits {
        get throws {
            try .init(
                maximumEventJSONByteCount: 200_000,
                maximumTagCount: 1,
                maximumTagElementCount: 2,
                maximumStringByteCount: 150_000
            )
        }
    }

    func candidate(
        for identity: Attempt.ControlIdentity
    ) throws -> MosaicPrivateDeploymentFixtures.CandidateKeyMaterial {
        let scalar = try #require(
            MosaicMainnetAlphaFixtures.scalarByte(for: identity)
        )
        return try .init(scalar: scalar)
    }

    func makeEvent(
        payload: Alpha.PreManifestNostrPayloadDocument,
        candidate: MosaicPrivateDeploymentFixtures.CandidateKeyMaterial,
        createdAt: UInt64,
        auxiliaryByte: UInt8
    ) throws -> Nostr.Event {
        try Alpha.PreManifestNostrCodec.makeEvent(
            for: payload,
            createdAtUnixSeconds: createdAt,
            using: candidate.signingKey,
            auxiliaryRandomness: .init(
                rawRepresentation: Data(repeating: auxiliaryByte, count: 32)
            ),
            limits: limits
        )
    }

}
