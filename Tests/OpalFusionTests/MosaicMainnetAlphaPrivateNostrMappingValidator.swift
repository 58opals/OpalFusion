// MosaicMainnetAlphaPrivateNostrMappingValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha private Nostr mapping validation", .serialized)
struct MosaicMainnetAlphaPrivateNostrMappingValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace

    @Test("Map the separate private selector to exact ephemeral kinds")
    func mapSeparatePrivateSelectorToExactEphemeralKinds() {
        let selector = Alpha.PrivateDeploymentNostrSelector.privateDeployment

        #expect(
            Alpha.PrivateDeploymentNostrSelector.identifier
                != OpalFusion.Mosaic.Profile.opalMainnetAlpha
                    .transportProfile.rawValue
        )
        #expect(selector.eventKind(for: .availabilityBeacon) == 26_540)
        #expect(selector.eventKind(for: .candidateSetAcknowledgement) == 26_541)
        #expect(selector.eventKind(for: .candidateAdmission) == 26_542)
        #expect(selector.eventKind(for: .roleCommitment) == 26_543)
        #expect(selector.eventKind(for: .roleReveal) == 26_544)
        #expect(
            selector.eventKind(for: .contributorNonceAllocation) == 26_546
        )
        #expect(selector.eventKind(for: .manifestProposal) == 26_545)
        #expect(selector.eventKind(for: .manifestSignature) == 26_545)
        #expect(selector.eventKind(for: .abort) == 26_547)
        #expect(selector.eventKind(for: .completion) == 26_548)
    }

    @Test("Round trip role commitment and reveal events")
    func roundTripRoleCommitmentAndRevealEvents() throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let epochStart = formation.discovery.epochStart
        let commitment = formation.commitments[0]
        let reveal = formation.reveals[0]
        let candidate = formation.controlCandidate(for: commitment.candidate)

        let commitmentPayload = try Alpha.PreManifestNostrPayloadDocument
            .makeRoleCommitment(
                commitment,
                controlRoster: formation.controlRoster
            )
        let commitmentEvent = try makeEvent(
            payload: commitmentPayload,
            candidate: candidate,
            createdAt: epochStart + 121,
            auxiliaryByte: 0xF1
        )
        #expect(
            try Alpha.PreManifestNostrCodec.decodeRoleCommitment(
                commitmentEvent,
                controlRoster: formation.controlRoster,
                currentUnixSeconds: epochStart + 121
            ) == commitment
        )

        let revealPayload = try Alpha.PreManifestNostrPayloadDocument
            .makeRoleReveal(
                reveal,
                controlRoster: formation.controlRoster
            )
        let revealEvent = try makeEvent(
            payload: revealPayload,
            candidate: candidate,
            createdAt: epochStart + 151,
            auxiliaryByte: 0xF2
        )
        #expect(
            try Alpha.PreManifestNostrCodec.decodeRoleReveal(
                revealEvent,
                controlRoster: formation.controlRoster,
                currentUnixSeconds: epochStart + 151
            ) == reveal
        )
    }
}
