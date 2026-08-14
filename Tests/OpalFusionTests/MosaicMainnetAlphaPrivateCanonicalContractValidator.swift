// MosaicMainnetAlphaPrivateCanonicalContractValidator.swift

import CryptoKit
import Foundation
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha private canonical contract validation", .serialized)
struct MosaicMainnetAlphaPrivateCanonicalContractValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt

    @Test("Freeze selector-bound canonical family digests")
    func freezeSelectorBoundCanonicalFamilyDigests() async throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let manifest = try MosaicPrivateDeploymentFixtures
            .makeManifestValidation(formation: formation)
        let proposal = try Alpha.PrivateDeploymentManifestProposalValidation(
            manifest: manifest
        )
        let signer = formation.roleElection.roster.controlIdentities[0]
        let signatureBody = try makeSignatureBody(
            signer: signer,
            formation: formation,
            manifest: manifest
        )
        let abortAuthority = try Alpha.PrivateDeploymentAbortAuthority
            .makeRoleSelectionAuthority(
                participant: signer,
                controlRoster: formation.controlRoster
            )
        let abort = try Alpha.PrivateDeploymentAbortDocument(
            discoveryEpochStartUnixSeconds: formation.discovery.epochStart,
            phase: .roleSelection,
            context: abortAuthority.context,
            reason: .timeout
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
        let payload = try Alpha.PreManifestNostrPayloadDocument
            .makeAvailabilityBeacon(formation.discovery.beacons[0])
        let registration = formation.discovery.relaySet.registrations[0]
        let acknowledgement = formation.acknowledgementSet
            .acknowledgements[0]
        let admission = formation.controlRoster.admissions[0]
        let families: [(String, [UInt8], String)] = [
            ("opaque-pool", formation.discovery.pool.canonicalBytes,
             "73faa531fc3d02b718d954ee1b3d6c6032d1c47b5a9f63cb3de79739fe5697ca"),
            ("relay-registration", registration.canonicalBytes,
             "498cafb6c9ff7f07e151ec4bef7cb49c537337d2f15baede08536966a0a92dca"),
            ("relay-set", formation.discovery.relaySet.canonicalBytes,
             "24e6e8760a4b44666427515df6da709cb733c1334c7390c6617cd4bb855e9ad2"),
            ("beacon-core", formation.discovery.beacons[0].core.canonicalBytes,
             "d7a9e0c4562846ce6f0ee03785ec5765a65d3c6b40bd8988737bb228d62e5d4e"),
            ("beacon", formation.discovery.beacons[0].canonicalBytes,
             "731a22de483090cee555cbba4b344b1582bdb29c6d63c0131e79917322224bb7"),
            ("candidate-selection", formation.selection.canonicalCandidateSetBytes,
             "4611f1c41dfa46db90ae76c584a6335682ec2976dd84f891ab3aab1ae7cd2c8f"),
            ("acknowledgement", formation.acknowledgementSet.acknowledgements[0].canonicalBytes,
             "f67f08905c0702aa003b6ca8a2d77d3ab718e8cd50039a9875ce505b839f2959"),
            ("acknowledgement-set", formation.acknowledgementSet.canonicalBytes,
             "387e06fc7d17792dccff35a27539a57c59bc080e1a46c866924e61543a7b56e0"),
            ("admission", formation.controlRoster.admissions[0].canonicalBytes,
             "3b6a5e33b735383f86861501f5bdae17d8ed36afe558cf81ad3cb7ddbc7a93fd"),
            ("control-roster", formation.controlRoster.canonicalAdmissionBytes,
             "c7e4cb610ea5c944ef710b677bc82330c30b56136a16f3beafa6ddfab42edabd"),
            ("nonce-allocation", formation.nonceAllocation.canonicalBytes,
             "2b2d103f204c13243dbb19d690d1a43a6bc497994b3437160cbd501eb4bf1812"),
            ("role-commitment", try Alpha.PreManifestDocumentCodec.encodeRoleCommitment(formation.commitments[0]),
             "5ebc17dde64467cf227b40c5a61b5603c270fc6de80fe37c63619b22bba30e5a"),
            ("role-reveal", try Alpha.PreManifestDocumentCodec.encodeRoleReveal(formation.reveals[0]),
             "1ecbbc49c883d5a42827f51b7da8ea8d49011cf431f2d0eb0ffbb0f9bac60642"),
            ("manifest-proposal", proposal.canonicalBody,
             "ff1973b179d6f3c4ec0a841e2f1505c4037caa9d08340bde9c8196032968bb35"),
            ("manifest-signature", signatureBody,
             "f0f92b68b9fc49265c5100a61fe51e919d5e172e88ade867db96193fa1c6f66d"),
            ("abort-context", abortAuthority.context.canonicalBytes,
             "e4ac5d536cdfa02d15f5bb46af63caab7fde78a21922c85fbc8e2959f0ee6855"),
            ("abort", abort.canonicalBytes,
             "0dbdf86cd28dbf83992ab3e462ec30a6f9b92242f192e40e32d87d7d6a1e1853"),
            ("completion", completion.canonicalBytes,
             "cae8db810a0936bdd9418437575fbf5f967c5b0a64e74c8fa7504ed2fa78f03e"),
            ("nostr-payload", payload.canonicalBytes,
             "6b8c3ac98bc58842e023a19e1a27178f78de03cb0be37f96f0c1634386227455"),
            ("proposal-binding", proposal.signatureBinding.manifestDigest,
             "82c3231f288f071dbf73b08d26a9deda75a1e9ab7768c4ff1bef3ac2aa68e1e5"),
        ]

        for (name, bytes, expectedDigest) in families {
            #expect(hexadecimal(Array(SHA256.hash(data: bytes))) == expectedDigest,
                    "Canonical family drifted: \(name)")
        }
        #expect(
            hexadecimal(registration.operatorIdentity.canonicalDigest)
                == "4b8d73995b591819a08607005599d58a3a1680474b6c1b295765f7297a4f4b29"
        )
        let discoveryAbortAuthority = try Alpha.PrivateDeploymentAbortAuthority
            .makeDiscoveryAuthority(
                beacon: formation.discovery.beacons[0],
                opaquePool: formation.discovery.pool,
                relaySet: formation.discovery.relaySet
            )
        let manifestAbortAuthority = try Alpha.PrivateDeploymentAbortAuthority
            .makeManifestAgreementAuthority(
                participant: signer,
                proposal: proposal
            )
        let acknowledgementSignatureDigest = try Alpha
            .CandidateSetAcknowledgementDocument.deriveSignatureDigest(
                discoveryEpochStartUnixSeconds:
                    acknowledgement.discoveryEpochStartUnixSeconds,
                candidateSetDigest: acknowledgement.candidateSetDigest,
                signerDiscoveryIdentity:
                    acknowledgement.signerDiscoveryIdentity,
                expiryUnixSeconds: acknowledgement.expiryUnixSeconds
            )
        let admissionSignatureDigest = try Alpha.CandidateAdmissionDocument
            .deriveSignatureDigest(
                discoveryEpochStartUnixSeconds:
                    admission.discoveryEpochStartUnixSeconds,
                candidateSetDigest: admission.candidateSetDigest,
                discoveryIdentity: admission.discoveryIdentity,
                controlIdentity: admission.controlIdentity,
                expiryUnixSeconds: admission.expiryUnixSeconds
            )
        let beaconSignatureDigest = Alpha.AvailabilityBeaconDocument
            .deriveSignatureDigest(
                core: formation.discovery.beacons[0].core,
                claimedWorkBitCount:
                    formation.discovery.beacons[0].claimedWorkBitCount
            )
        let protocolDomainOutputs: [(String, [UInt8], String)] = [
            ("opaque-pool", formation.discovery.pool.digest,
             "8485070aa47967aec23bd5764e8e0adb17abfbd386f3453c6ca13c7bffd1a5ec"),
            ("relay-set", formation.discovery.relaySet.digest,
             "70687e218b4976d7cbe158399aa599ec49dd16afb16115106d4f6d5f2a5d9fb9"),
            ("beacon-work", formation.discovery.beacons[0].core.workDigest,
             "00000999b44cf4d9cb69d1a51f3e6f2e732ea7bcd70aff53c23794cc245cd06e"),
            ("beacon-signature", beaconSignatureDigest,
             "395ab3a9d0e38a6e77c7c54c1c594f74636a9b4356514ac282fb6d8efba7be7a"),
            ("candidate-set", formation.selection.candidateSetDigest,
             "489e02a900b1c9d4c5295a785315db65027a3f4ce9e4e2738b1cc0c0c8822a5b"),
            ("acknowledgement-signature", acknowledgementSignatureDigest,
             "f7c2e9ff86ac9a4f5ca8dec25367948573f9f8f82d87c78b3be2a4a6f8aefa0f"),
            ("admission-signature", admissionSignatureDigest,
             "ebd1b18accda360f62ce9dfaf7bb287b3408f43ba6eef42edbd1b4618fcfcc24"),
            ("control-roster", formation.controlRoster.controlRosterDigest,
             "c01cbee21a2ef6c241a05e8e67820a03a0dad6964dd3c969c3a14ff5b2b3607b"),
            ("nonce-allocation", formation.nonceAllocation.digest,
             "03efe86e6dc906bb9557ebde3b2d1511843684432ff373ef1f7888c94f51104b"),
            ("discovery-context", discoveryAbortAuthority.context.digest,
             "f0a6599fcd6d92fe27ba998a9e389ba530ec0ca83dcba294d4b305cc84e544c3"),
            ("manifest-context", manifestAbortAuthority.context.digest,
             "f7b332616d6d64c7a26d68f8967718fcb901e9afa17fccc9c693035b28279821"),
            ("proposal-binding", proposal.signatureBinding.manifestDigest,
             "d0f713d50afbe2fbc9bcf2934df8fbbb361ec4d89088254da6c477c0138af806"),
        ]
        for (name, output, expectedHexadecimal) in protocolDomainOutputs {
            #expect(
                hexadecimal(output) == expectedHexadecimal,
                "Protocol domain output drifted: \(name)"
            )
        }
    }

    func makeSignatureBody(
        signer: Attempt.ControlIdentity,
        formation: MosaicPrivateDeploymentFixtures.Formation,
        manifest: Alpha.PrivateDeploymentManifestValidation
    ) throws -> [UInt8] {
        let signerCandidate = formation.controlCandidate(for: signer)
        let signature = Attempt.ManifestSignature(
            signer: signer,
            rawRepresentation: try MosaicPrivateDeploymentFixtures.sign(
                digestBytes: manifest.core.roundIdentifier,
                using: signerCandidate.signingKey,
                auxiliaryByte: 0xD1
            )
        )
        return try Alpha.PreManifestDocumentCodec
            .encodeManifestSignature(signature)
    }

    func hexadecimal(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
