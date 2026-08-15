// OpalFusion+MosaicPrivateAlphaRuntime+Owner+Publication.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime.Owner {
    /// Installs a two-relay accepted receipt only for the exact persisted signed event.
    @_spi(MosaicPrivateAlpha)
    public func acknowledgePrivateDeploymentPublication(
        consuming receipt: consuming OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentPublicationReceipt
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        let expected: Runtime.PrivateDeploymentPublication
        switch state.publicationState {
        case .none:
            throw Runtime.Failure.invalidStateTransition
        case let .formation(event, endpoints),
             let .terminal(_, event, endpoints, _):
            expected = try .init(
                binding: state.binding,
                event: event,
                relayEndpointIdentifiers: endpoints
            )
        }
        guard receipt.operationIdentifier == expected.operationIdentifier else {
            throw Runtime.Failure.invalidStateTransition
        }
        return try stagePublicationResolution { candidate in
            switch candidate.publicationState {
            case .none:
                throw Runtime.Failure.invalidStateTransition
            case .formation:
                candidate.publicationState = .none
            case let .terminal(reason, _, _, evidence):
                candidate.publicationState = .none
                candidate.terminalState = .authorized(
                    reason,
                    exactEvidenceBytes: evidence
                )
            }
        }
    }
}
#endif
