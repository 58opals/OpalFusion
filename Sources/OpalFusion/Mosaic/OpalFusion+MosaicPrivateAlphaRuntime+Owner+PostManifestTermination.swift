// OpalFusion+MosaicPrivateAlphaRuntime+Owner+PostManifestTermination.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime.Owner {
    /// Routes one claimed post-manifest termination through its package-owned provenance.
    ///
    /// Received terminal events and an already persisted local timeout never require a
    /// new signature. A locally derived completion or non-timeout abort requires the
    /// caller's one-use signing capability. Non-protocol runtime failures remain
    /// recovery-required and are rejected instead of manufacturing terminal evidence.
    @_spi(MosaicPrivateAlpha)
    public func preparePostManifestTermination(
        consuming termination: consuming OpalFusion
            .MosaicPrivateAlphaRuntime.PostManifestTermination,
        createdAtUnixSeconds: UInt64,
        signing: consuming OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentSigningCapability?
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime

        switch termination.kind {
        case .completed:
            if termination.receivedTerminalEvent != nil {
                return try acceptReceivedConductorCompletion(
                    consuming: termination
                )
            }
            guard termination.localTerminalEvent == nil,
                  let signing else {
                throw Runtime.Failure.terminalEvidenceUnavailable
            }
            return try prepareTerminalPublication(
                consuming: termination,
                createdAtUnixSeconds: createdAtUnixSeconds,
                signing: signing
            )
        case .aborted:
            if termination.receivedTerminalEvent != nil {
                return try acceptReceivedAbortTermination(
                    consuming: termination
                )
            }
            if termination.localTerminalEvent != nil {
                return try preparePersistedTimeoutPublication(
                    consuming: termination
                )
            }
            guard let signing else {
                throw Runtime.Failure.terminalEvidenceUnavailable
            }
            return try prepareTerminalPublication(
                consuming: termination,
                createdAtUnixSeconds: createdAtUnixSeconds,
                signing: signing
            )
        case .failed, .recoveryRequired, .transportFailed:
            throw Runtime.Failure.terminalEvidenceUnavailable
        }
    }
}
#endif
