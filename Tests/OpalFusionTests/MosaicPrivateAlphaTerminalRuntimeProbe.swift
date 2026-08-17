// MosaicPrivateAlphaTerminalRuntimeProbe.swift

@_spi(MosaicPrivateAlpha) @testable import OpalFusion

actor MosaicPrivateAlphaTerminalRuntimeProbe {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias FanIn = Alpha.PostManifestRelayFanIn

    private let phase: Attempt.Phase
    private var terminalState: Alpha.PostManifestRuntimeDriver.State?
    private var terminalAbort: (
        phase: Attempt.Phase,
        reason: Attempt.AbortReason
    )?

    init(phase: Attempt.Phase) {
        self.phase = phase
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
            stop: {},
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
