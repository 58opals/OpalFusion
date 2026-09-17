// MosaicPrivateAlphaTerminalRuntimeProbe.swift

@_spi(MosaicPrivateAlpha) @testable import OpalFusion

actor MosaicPrivateAlphaTerminalRuntimeProbe {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias FanIn = Alpha.PostManifestRelayFanIn

    private let phase: Attempt.Phase
    private let stopState: Alpha.PostManifestRuntimeDriver.State?
    private(set) var stopCount = 0
    private var terminalState: Alpha.PostManifestRuntimeDriver.State?
    private var terminalAbort: (
        phase: Attempt.Phase,
        reason: Attempt.AbortReason
    )?

    init(
        phase: Attempt.Phase,
        stopState: Alpha.PostManifestRuntimeDriver.State? = nil
    ) {
        self.phase = phase
        self.stopState = stopState
    }

    func endpoint() -> FanIn.RuntimeEndpoint {
        .init(
            start: { true },
            state: {
                if let terminalState = await self.terminalState {
                    return .terminal(terminalState)
                }
                return .running
            },
            submit: { _ in .rejected(.notRunning) },
            inputSourceDidTerminate: { _ in false },
            stop: { await self.stop() },
            waitForTermination: { await self.terminalState },
            currentPhase: { self.phase },
            terminalProtocolAbort: { await self.terminalAbort },
            submitAuthenticatedAbort: { phase, reason in
                await self.applyAbort(phase: phase, reason: reason)
            },
            submitOrderedAuthenticatedAbort: { operation in
                await self.applyAbort(deriving: operation)
            }
        )
    }

    private func stop() {
        stopCount += 1
        if terminalState == nil { terminalState = stopState }
    }

    private func applyAbort(
        phase: Attempt.Phase,
        reason: Attempt.AbortReason
    ) -> Bool {
        guard phase == self.phase, terminalState == nil else { return false }
        terminalAbort = (phase, reason)
        terminalState = .contributor(
            .terminal(.cancelled(during: phase))
        )
        return true
    }

    private func applyAbort(
        deriving operation: @escaping @Sendable (Attempt.Phase) throws
            -> Attempt.AbortReason
    ) -> Bool {
        guard terminalState == nil,
              let reason = try? operation(phase) else {
            return false
        }
        return applyAbort(phase: phase, reason: reason)
    }
}
