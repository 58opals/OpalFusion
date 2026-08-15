// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentFormationRestoration.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    static func restorePrivateDeploymentFormation(
        discoveryEpochStartUnixSeconds: UInt64,
        phase: Phase,
        canonicalDocuments: [Data]
    ) throws -> PrivateDeploymentFormationState {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Attempt = OpalFusion.Mosaic.Attempt

        do {
            guard phase.isPreManifest else {
                throw Failure.invalidPrivateDeploymentProof
            }
            guard !canonicalDocuments.isEmpty else {
                guard phase == .discovery else {
                    throw Failure.invalidPrivateDeploymentProof
                }
                return .uninitialized
            }
            guard canonicalDocuments.count >= 2 else {
                throw Failure.invalidPrivateDeploymentProof
            }
            let pool = try Alpha.OpaquePoolDocument.decode(
                from: Array(canonicalDocuments[0])
            )
            let relaySet = try Alpha.RelaySetDocument.decode(
                from: Array(canonicalDocuments[1])
            )
            guard Data(pool.canonicalBytes) == canonicalDocuments[0],
                  Data(relaySet.canonicalBytes) == canonicalDocuments[1] else {
                throw Failure.invalidPrivateDeploymentProof
            }
            let storedEvents = try canonicalDocuments.dropFirst(2).map(
                PrivateDeploymentEvent.decodeRecoveryBytes
            )
            let nostrEvents = try storedEvents.map {
                try $0.decodeCanonicalNostrEvent()
            }
            var cursor = 0
            func take(
                _ payloadKind: Alpha.PrivateDeploymentNostrSelector.PayloadKind
            ) -> (records: [PrivateDeploymentEvent], events: [
                OpalFusion.Mosaic.NostrNamespace.Event
            ]) {
                let kind = Alpha.PrivateDeploymentNostrSelector
                    .privateDeployment.eventKind(for: payloadKind)
                let start = cursor
                while cursor < nostrEvents.count,
                      nostrEvents[cursor].template.kind == kind {
                    cursor += 1
                }
                return (
                    Array(storedEvents[start ..< cursor]),
                    Array(nostrEvents[start ..< cursor])
                )
            }
            func requireCanonicalSignerOrder(
                _ events: [OpalFusion.Mosaic.NostrNamespace.Event]
            ) throws {
                for index in events.indices.dropFirst() {
                    guard events[index - 1].publicKey.rawRepresentation
                            .lexicographicallyPrecedes(
                                events[index].publicKey.rawRepresentation
                            ) else {
                        throw Failure.invalidPrivateDeploymentProof
                    }
                }
            }

            let beaconGroup = take(.availabilityBeacon)
            let beacons = try zip(beaconGroup.records, beaconGroup.events).map {
                stored, event in
                let beacon = try Alpha.PreManifestNostrCodec
                    .decodeAvailabilityBeacon(
                        event,
                        discoveryEpochStartUnixSeconds:
                            discoveryEpochStartUnixSeconds,
                        currentUnixSeconds: stored.acceptedAtUnixSeconds
                    )
                guard beacon.core.opaquePoolIdentifier
                        == pool.opaqueIdentifier,
                      beacon.core.relaySetDigest == relaySet.digest else {
                    throw Failure.invalidPrivateDeploymentProof
                }
                return beacon
            }
            if phase == .discovery {
                guard cursor == nostrEvents.endIndex else {
                    throw Failure.invalidPrivateDeploymentProof
                }
                try requireCanonicalSignerOrder(beaconGroup.events)
                return .discovery(
                    pool: pool,
                    relaySet: relaySet,
                    events: beaconGroup.records,
                    beacons: beacons
                )
            }

            let candidateSelection = try Alpha.CandidateSelectionValidation(
                beacons: beacons,
                discoveryEpochStartUnixSeconds:
                    discoveryEpochStartUnixSeconds,
                opaquePool: pool,
                relaySet: relaySet
            )
            guard beacons == candidateSelection.selectedBeacons,
                  beaconGroup.records.count == beacons.count else {
                throw Failure.invalidPrivateDeploymentProof
            }

            let acknowledgementGroup = take(.candidateSetAcknowledgement)
            try requireCanonicalSignerOrder(acknowledgementGroup.events)
            let acknowledgements = try zip(
                acknowledgementGroup.records,
                acknowledgementGroup.events
            ).map { stored, event in
                try Alpha.PreManifestNostrCodec
                    .decodeCandidateSetAcknowledgement(
                        event,
                        candidateSelection: candidateSelection,
                        currentUnixSeconds: stored.acceptedAtUnixSeconds
                    )
            }
            guard acknowledgements.count <= beacons.count else {
                throw Failure.invalidPrivateDeploymentProof
            }
            if phase == .candidateSetAgreement {
                guard cursor == nostrEvents.endIndex else {
                    throw Failure.invalidPrivateDeploymentProof
                }
                return .candidateSetAgreement(
                    selection: candidateSelection,
                    events: acknowledgementGroup.records,
                    acknowledgements: acknowledgements
                )
            }
            let acknowledgementSet = try Alpha
                .CandidateSetAcknowledgementSetDocument(
                    acknowledgements: acknowledgements,
                    candidateSelection: candidateSelection
                )
            guard acknowledgementSet.acknowledgements == acknowledgements else {
                throw Failure.invalidPrivateDeploymentProof
            }

            let admissionGroup = take(.candidateAdmission)
            try requireCanonicalSignerOrder(admissionGroup.events)
            let admissions = try zip(
                admissionGroup.records,
                admissionGroup.events
            ).map { stored, event in
                try Alpha.PreManifestNostrCodec.decodeCandidateAdmission(
                    event,
                    candidateSelection: candidateSelection,
                    acknowledgementSet: acknowledgementSet,
                    currentUnixSeconds: stored.acceptedAtUnixSeconds
                )
            }
            guard admissions.count <= beacons.count else {
                throw Failure.invalidPrivateDeploymentProof
            }
            if phase == .admission {
                guard cursor == nostrEvents.endIndex else {
                    throw Failure.invalidPrivateDeploymentProof
                }
                return .admission(
                    selection: candidateSelection,
                    acknowledgementSet: acknowledgementSet,
                    events: admissionGroup.records,
                    admissions: admissions
                )
            }
            let controlRoster = try Alpha.ControlRosterValidation(
                admissions: admissions,
                candidateSelection: candidateSelection,
                acknowledgementSet: acknowledgementSet
            )
            guard controlRoster.admissions == admissions else {
                throw Failure.invalidPrivateDeploymentProof
            }

            let commitmentGroup = take(.roleCommitment)
            try requireCanonicalSignerOrder(commitmentGroup.events)
            let commitments = try zip(
                commitmentGroup.records,
                commitmentGroup.events
            ).map { stored, event in
                try Alpha.PreManifestNostrCodec.decodeRoleCommitment(
                    event,
                    controlRoster: controlRoster,
                    currentUnixSeconds: stored.acceptedAtUnixSeconds
                )
            }
            guard commitments.count <= beacons.count else {
                throw Failure.invalidPrivateDeploymentProof
            }
            if phase == .controlRosterAgreement {
                guard cursor == nostrEvents.endIndex else {
                    throw Failure.invalidPrivateDeploymentProof
                }
                return .controlRosterAgreement(
                    controlRoster: controlRoster,
                    events: commitmentGroup.records,
                    commitments: commitments
                )
            }
            let commitmentSet = try Attempt.RoleCommitmentSet(
                controlRoster: controlRoster.controlRosterBinding,
                commitments: commitments
            )
            guard commitmentSet.commitments == commitments else {
                throw Failure.invalidPrivateDeploymentProof
            }

            let revealGroup = take(.roleReveal)
            try requireCanonicalSignerOrder(revealGroup.events)
            let reveals = try zip(
                revealGroup.records,
                revealGroup.events
            ).map { stored, event in
                try Alpha.PreManifestNostrCodec.decodeRoleReveal(
                    event,
                    controlRoster: controlRoster,
                    currentUnixSeconds: stored.acceptedAtUnixSeconds
                )
            }
            guard reveals.count <= beacons.count else {
                throw Failure.invalidPrivateDeploymentProof
            }
            if phase == .roleElection {
                guard cursor == nostrEvents.endIndex else {
                    throw Failure.invalidPrivateDeploymentProof
                }
                return .roleElection(
                    controlRoster: controlRoster,
                    commitmentSet: commitmentSet,
                    events: revealGroup.records,
                    reveals: reveals
                )
            }
            let roleSeed = try Attempt.RoleSeedValidation(
                profile: .opalMainnetAlpha,
                commitmentSet: commitmentSet,
                reveals: reveals,
                using: Alpha.RoleSeedValidator()
            )
            guard roleSeed.revealSet.reveals == reveals else {
                throw Failure.invalidPrivateDeploymentProof
            }
            let roleElection = try Attempt.RoleElectionResult(
                profile: .opalMainnetAlpha,
                commitmentSet: commitmentSet,
                validation: roleSeed
            )

            let nonceGroup = take(.contributorNonceAllocation)
            guard nonceGroup.records.count <= 1 else {
                throw Failure.invalidPrivateDeploymentProof
            }
            if phase == .nonceAllocation {
                guard cursor == nostrEvents.endIndex else {
                    throw Failure.invalidPrivateDeploymentProof
                }
                guard let stored = nonceGroup.records.first,
                      let event = nonceGroup.events.first else {
                    return .nonceAllocationPending(
                        controlRoster: controlRoster,
                        roleElection: roleElection
                    )
                }
                _ = try Alpha.PreManifestNostrCodec
                    .decodeContributorNonceAllocation(
                        event,
                        controlRoster: controlRoster,
                        roleElection: roleElection,
                        currentUnixSeconds: stored.acceptedAtUnixSeconds
                    )
                return .nonceAllocationAccepted(
                    controlRoster: controlRoster,
                    roleElection: roleElection
                )
            }
            guard let nonceStored = nonceGroup.records.first,
                  let nonceEvent = nonceGroup.events.first else {
                throw Failure.invalidPrivateDeploymentProof
            }
            let nonceAllocation = try Alpha.PreManifestNostrCodec
                .decodeContributorNonceAllocation(
                    nonceEvent,
                    controlRoster: controlRoster,
                    roleElection: roleElection,
                    currentUnixSeconds: nonceStored.acceptedAtUnixSeconds
                )

            let manifestGroup = take(.manifestProposal)
            guard cursor == nostrEvents.endIndex else {
                throw Failure.invalidPrivateDeploymentProof
            }
            let proposalContext = try Alpha.ManifestProposalContext(
                roleElection: roleElection,
                candidateSetDigest: candidateSelection.candidateSetDigest,
                opaquePoolIdentifier: pool.opaqueIdentifier
            )
            guard let proposalStored = manifestGroup.records.first,
                  let proposalEvent = manifestGroup.events.first else {
                return .manifestProposalPending(
                    pool: pool,
                    relaySet: relaySet,
                    candidateSelection: candidateSelection,
                    controlRoster: controlRoster,
                    roleElection: roleElection,
                    nonceAllocation: nonceAllocation
                )
            }
            let manifestCore = try Alpha.PreManifestNostrCodec
                .decodeManifestProposalCandidate(
                    proposalEvent,
                    discoveryEpochStartUnixSeconds:
                        discoveryEpochStartUnixSeconds,
                    proposalContext: proposalContext,
                    currentUnixSeconds: proposalStored.acceptedAtUnixSeconds
                )
            let manifestValidation = try Alpha
                .PrivateDeploymentManifestValidation(
                    discoveryEpochStartUnixSeconds:
                        discoveryEpochStartUnixSeconds,
                    core: manifestCore,
                    candidateSelection: candidateSelection,
                    controlRoster: controlRoster,
                    roleElection: roleElection,
                    opaquePool: pool,
                    relaySet: relaySet,
                    nonceAllocation: nonceAllocation
                )
            let proposal = try Alpha
                .PrivateDeploymentManifestProposalValidation(
                    manifest: manifestValidation
                )
            guard try Alpha.PreManifestNostrCodec.decodeManifestProposal(
                proposalEvent,
                proposal: proposal,
                currentUnixSeconds: proposalStored.acceptedAtUnixSeconds
            ) == manifestCore else {
                throw Failure.invalidPrivateDeploymentProof
            }
            let signatureRecords = Array(manifestGroup.records.dropFirst())
            let signatureEvents = Array(manifestGroup.events.dropFirst())
            try requireCanonicalSignerOrder(signatureEvents)
            let signatures = try zip(signatureRecords, signatureEvents).map {
                stored, event in
                try Alpha.PreManifestNostrCodec.decodeManifestSignature(
                    event,
                    proposal: proposal,
                    currentUnixSeconds: stored.acceptedAtUnixSeconds
                )
            }
            guard signatures.count <= beacons.count else {
                throw Failure.invalidPrivateDeploymentProof
            }
            return .manifestSignatures(
                proposal: proposal,
                events: signatureRecords,
                signatures: signatures
            )
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.invalidPrivateDeploymentProof
        }
    }
}
#endif
