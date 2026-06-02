// OpalFusion+Runtime+LiveRuntimeDriver+ImplementationGroup2.swift

import Foundation
import OpalDiagnostics

extension OpalFusion.Runtime.LiveRuntimeDriver {
    func handle(
        _ input: OpalFusion.Runtime.PrimaryRuntimeSession.Input
    ) async {
        let failureAllowsReconnect = canReconnectAfter(input)
        let effects = runtimeSession.apply(
            input: input,
            now: await nowProvider()
        )

        for effect in effects {
            await process(effect)

            if hasTerminalConnectionState {
                break
            }
        }

        let shouldCancelRoundScopedTasks = runtimeSession.engine.session.connectionSubstate != .inRound
        let reachedTerminalConnectionState = hasTerminalConnectionState
        let shouldProjectPreRoundDisconnect = reachedTerminalConnectionState &&
            runtimeSession.engine.round == nil &&
            runtimeSession.clientState.isConnected

        if shouldCancelRoundScopedTasks {
            cancelCovertTasks()
            cancelHostTasks()
            if let covertTransport {
                await covertTransport.reset()
            }
        }

        if reachedTerminalConnectionState {
            lastFailureAllowsReconnect = lastFailureAllowsReconnect ||
                (
                    failureAllowsReconnect &&
                        runtimeSession.lastError == .transportUnavailable
                )
            await emitSnapshotIfNeeded()
            await tearDownTransports()
            if shouldProjectPreRoundDisconnect {
                await handle(.disconnected)
            }
            return
        }

        lastFailureAllowsReconnect = false
        await emitSnapshotIfNeeded()
    }
}
