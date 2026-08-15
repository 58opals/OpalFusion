// OpalFusion+Mosaic+OpalMainnetAlpha+PreManifestNostrCodec~ManifestProposalCandidate.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha.PreManifestNostrCodec {
    static func decodeManifestProposalCandidate(
        _ event: OpalFusion.Mosaic.NostrNamespace.Event,
        discoveryEpochStartUnixSeconds: UInt64,
        proposalContext: OpalFusion.Mosaic.OpalMainnetAlpha
            .ManifestProposalContext,
        currentUnixSeconds: UInt64
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifestCore {
        let roster = proposalContext.roleElection.roster
        let context = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrValidationContext.makePreManifestContext(
                epochStart: discoveryEpochStartUnixSeconds,
                signerRole: .conductor,
                signerIdentity: .init(
                    rawRepresentation: .init(
                        roster.conductor.validatedBytes
                    )
                ),
                payloadKind: .manifestProposal,
                currentUnixSeconds: currentUnixSeconds
            )
        let payload = try decode(event, validating: context)
        guard payload.payloadKind == .manifestProposal else {
            throw ValidationError.payloadKindMismatch
        }
        let core = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestDocumentCodec.decodeManifestProposal(
                from: payload.body,
                expectedContext: proposalContext
            )
        guard core.roster.conductor.validatedBytes
                == [UInt8](payload.signerIdentity.rawRepresentation) else {
            throw ValidationError.bodySignerIdentityMismatch
        }
        return core
    }
}
