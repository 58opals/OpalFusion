// OpalFusion+Runtime+LiveRuntimeDriver+ImplementationGroup1.swift

import Foundation
import OpalDiagnostics

extension OpalFusion.Runtime.LiveRuntimeDriver {
    func start() async {
        guard isRunning == false else {
            return
        }
        isRunning = true
        stopRequested = false
        lastFailureAllowsReconnect = false

        if let summary = OpalFusion.Runtime.validateStartupConfiguration(
            runtimeSession.engine.session.configuration,
            genesisHash: runtimeSession.engine.session.genesisHash,
            joinPools: runtimeSession.engine.session.joinPools
        ) {
            await handle(.invalidConfiguration(summary: summary))
            await tearDownTransports()
            return
        }

        if primaryTransport == nil {
            primaryTransport = await primaryTransportFactory(configuration)
        }
        if covertTransport == nil {
            covertTransport = await covertTransportFactory(configuration)
        }

        guard let primaryTransport else {
            await handle(
                .primaryTransportFailed(
                    summary: "Primary transport was unavailable"
                )
            )
            await tearDownTransports()
            return
        }

        do {
            recordPrimaryConnect(OpalDiagnostics.Event.primaryConnectStarted)
            let inboundStream = try await primaryTransport.connect()
            recordPrimaryConnect(OpalDiagnostics.Event.primaryConnectSucceeded)
            startPrimaryReadLoop(inboundStream)
            await handle(.connected)
            if isRunning {
                startClockLoop()
            }
        } catch {
            if stopRequested,
               Self.shouldIgnorePrimaryTransportCancellation(error) {
                return
            }

            recordPrimaryConnect(
                OpalDiagnostics.Event.primaryConnectFailed,
                error: error
            )
            await handle(
                .diagnosedPrimaryTransportFailed(
                    summary: "Primary connection failed"
                )
            )
            await tearDownTransports()
        }
    }

    func stop() async {
        guard isRunning else {
            return
        }

        stopRequested = true
        await handle(.stopped)
    }

    func recordPrimaryConnect(
        _ event: OpalDiagnostics.Event,
        error: Error? = nil
    ) {
        let errorFields = error.map { OpalDiagnostics.Field.errorFields(for: $0) } ?? []
        OpalDiagnostics.logger(category: .fusionPrimary).record(
            event: event,
            level: .opalFusionDefault(for: event),
            fields: [
                .operation("primary_connect")
            ] + errorFields
        )
    }

    func startPrimaryReadLoop(
        _ inboundStream: AsyncThrowingStream<[UInt8], Error>
    ) {
        primaryReadTask?.cancel()
        primaryReadTask = Task { [inboundStream] in
            do {
                for try await bytes in inboundStream {
                    await self.handle(.receivedPrimaryBytes(bytes))
                }
                guard Task.isCancelled == false else {
                    return
                }
                self.logPreRoundDisconnectIfNeeded()
                await self.handle(.disconnected)
            } catch {
                guard Task.isCancelled == false,
                      Self.shouldIgnorePrimaryTransportCancellation(error) == false else {
                    return
                }
                self.recordPrimaryReadFailure(error)
                await self.handle(
                    .diagnosedPrimaryTransportFailed(
                        summary: "Primary read failed"
                    )
                )
            }
        }
    }

    func recordPrimaryReadFailure(_ error: Error) {
        OpalDiagnostics.logger(category: .fusionTransport).record(
            event: .transportError,
            level: .opalFusionDefault(for: .transportError),
            traceID: .opalFusionRound(runtimeSession.engine.round?.identifier),
            fields: [
                .operation("primary_read")
            ] + OpalDiagnostics.Field.errorFields(for: error)
        )
    }

    static func shouldIgnorePrimaryTransportCancellation(
        _ error: Error
    ) -> Bool {
        if error is CancellationError {
            return true
        }

        if let transportError = error as? OpalFusion.Runtime.LiveTransportError,
           transportError == .primaryConnectionCancelled {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == Int(ECANCELED) {
            return true
        }

        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled {
            return true
        }

        return false
    }

    func startClockLoop() {
        clockTask?.cancel()
        clockTask = Task { [clockTickInterval] in
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(for: clockTickInterval)
                } catch {
                    return
                }

                if Task.isCancelled {
                    return
                }

                await self.handle(.clockAdvanced)
            }
        }
    }
}
