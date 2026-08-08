// MosaicRuntimeSessionDriverValidator.swift

import Testing
@testable import OpalFusion

@Suite("Mosaic runtime-session driver validation")
struct MosaicRuntimeSessionDriverValidator {
    typealias Driver = OpalFusion.Mosaic.RuntimeSessionDriver

    @Test("Reject the incomplete generic draft before opening an input source")
    func rejectDraftProfile() throws {
        let source = MosaicRuntimeSessionDriverInputProbe()
        let sink = MosaicRuntimeSessionDriverOutputProbe()

        #expect(
            throws: Driver.InitializationError.unsupportedProfile(.draft1)
        ) {
            _ = try Driver(
                runtimeSession: MosaicRuntimeSessionDriverFixture.makeSession(
                    profile: .draft1
                ),
                dependencies: dependencies(source: source, sink: sink)
            )
        }
    }

    @Test("Reject an already-terminal session before opening an input source")
    func rejectTerminalSession() throws {
        let source = MosaicRuntimeSessionDriverInputProbe()
        let sink = MosaicRuntimeSessionDriverOutputProbe()
        var session = try MosaicRuntimeSessionDriverFixture.makeSession()
        _ = session.apply(input: .local(.retryRequested))

        #expect(
            throws: Driver.InitializationError.terminalSession(
                .failed(.inPlaceRetryNotPermitted)
            )
        ) {
            _ = try Driver(
                runtimeSession: session,
                dependencies: dependencies(source: source, sink: sink)
            )
        }
    }

    @Test("Start and stop are idempotent for one attempt", .timeLimit(.minutes(1)))
    func startAndStopOnce() async throws {
        let source = MosaicRuntimeSessionDriverInputProbe()
        let sink = MosaicRuntimeSessionDriverOutputProbe()
        let driver = try makeDriver(source: source, sink: sink)

        await driver.start()
        await driver.start()
        await source.waitUntilOpened()
        await driver.stop()
        await driver.stop()

        #expect(await source.openCount == 1)
        #expect(await source.closeCount == 1)
        #expect(
            await driver.state
                == .terminal(.cancelled(.requested(during: .manifestAgreement)))
        )
        #expect(
            sink.outputs == [
                .runtimeEffect(
                    .localAttempt(
                        .attemptTerminated(
                            .cancelled(.requested(during: .manifestAgreement))
                        )
                    )
                )
            ]
        )
    }

    @Test("The first terminal input permanently stops consumption", .timeLimit(.minutes(1)))
    func stopAtFirstTerminalInput() async throws {
        let source = MosaicRuntimeSessionDriverInputProbe()
        let sink = MosaicRuntimeSessionDriverOutputProbe()
        let driver = try makeDriver(source: source, sink: sink)

        await driver.start()
        await source.waitUntilOpened()
        await source.send(.local(.retryRequested))
        await source.send(.local(.cancel))
        await source.finish()
        await driver.waitForTermination()

        #expect(await source.closeCount == 1)
        #expect(
            await driver.state
                == .terminal(.failed(.inPlaceRetryNotPermitted))
        )
        #expect(
            sink.outputs == [
                .runtimeEffect(
                    .localAttempt(
                        .attemptTerminated(.failed(.inPlaceRetryNotPermitted))
                    )
                )
            ]
        )
    }

    @Test("End of input cancels locally before reporting the cause", .timeLimit(.minutes(1)))
    func cancelWhenInputEnds() async throws {
        let source = MosaicRuntimeSessionDriverInputProbe()
        let sink = MosaicRuntimeSessionDriverOutputProbe()
        let driver = try makeDriver(
            target: .walletReservation,
            source: source,
            sink: sink
        )

        await driver.start()
        await source.waitUntilOpened()
        await source.finish()
        await driver.waitForTermination()

        #expect(await source.closeCount == 1)
        #expect(sink.outputs.count == 3)
        if case .runtimeEffect(
            .localAttempt(.walletReservationReleaseRequired)
        ) = sink.outputs[0] {
            // Expected.
        } else {
            Issue.record("Expected source completion to release the reservation")
        }
        #expect(
            sink.outputs[1]
                == .runtimeEffect(
                    .localAttempt(
                        .attemptTerminated(
                            .cancelled(.requested(during: .walletReservation))
                        )
                    )
                )
        )
        #expect(sink.outputs[2] == .inputSourceTerminated(.finished))
        #expect(sink.cancellationStates == [false, false, false])
    }

    @Test("Input failure cancels locally without exporting its error", .timeLimit(.minutes(1)))
    func cancelWhenInputFails() async throws {
        let source = MosaicRuntimeSessionDriverInputProbe()
        let sink = MosaicRuntimeSessionDriverOutputProbe()
        let driver = try makeDriver(
            target: .walletReservation,
            source: source,
            sink: sink
        )

        await driver.start()
        await source.waitUntilOpened()
        await source.fail()
        await driver.waitForTermination()

        #expect(await source.closeCount == 1)
        #expect(sink.outputs.count == 3)
        if case .runtimeEffect(
            .localAttempt(.walletReservationReleaseRequired)
        ) = sink.outputs[0] {
            // Expected.
        } else {
            Issue.record("Expected source failure to release the reservation")
        }
        #expect(
            sink.outputs[1]
                == .runtimeEffect(
                    .localAttempt(
                        .attemptTerminated(
                            .cancelled(.requested(during: .walletReservation))
                        )
                    )
                )
        )
        #expect(sink.outputs[2] == .inputSourceTerminated(.failed))
        #expect(sink.cancellationStates == [false, false, false])
    }

    @Test("Reservation release is emitted before terminal outcome", .timeLimit(.minutes(1)))
    func emitReservationReleaseBeforeTerminal() async throws {
        let source = MosaicRuntimeSessionDriverInputProbe()
        let sink = MosaicRuntimeSessionDriverOutputProbe()
        let driver = try makeDriver(
            target: .walletReservation,
            source: source,
            sink: sink
        )

        await driver.start()
        await source.waitUntilOpened()
        await driver.stop()

        #expect(sink.outputs.count == 2)
        if case .runtimeEffect(
            .localAttempt(.walletReservationReleaseRequired)
        ) = sink.outputs[0] {
            // Expected.
        } else {
            Issue.record("Expected reservation release before terminal output")
        }
        #expect(
            sink.outputs[1]
                == .runtimeEffect(
                    .localAttempt(
                        .attemptTerminated(
                            .cancelled(.requested(during: .walletReservation))
                        )
                    )
                )
        )
    }

    @Test(
        "Stream-driven cancellation emits reservation cleanup uncancelled",
        .timeLimit(.minutes(1))
    )
    func emitStreamCancellationUncancelled() async throws {
        let source = MosaicRuntimeSessionDriverInputProbe()
        let sink = MosaicRuntimeSessionDriverOutputProbe()
        let driver = try makeDriver(
            target: .walletReservation,
            source: source,
            sink: sink
        )

        await driver.start()
        await source.waitUntilOpened()
        await source.send(.local(.cancel))
        await driver.waitForTermination()

        #expect(await source.closeCount == 1)
        #expect(sink.outputs.count == 2)
        #expect(sink.cancellationStates == [false, false])
        if case .runtimeEffect(
            .localAttempt(.walletReservationReleaseRequired)
        ) = sink.outputs[0] {
            // Expected.
        } else {
            Issue.record("Expected stream cancellation to emit reservation release")
        }
    }

    @Test(
        "A validated signing result commits before completing uncancelled",
        .timeLimit(.minutes(1))
    )
    func emitCommitBeforeCompletionUncancelled() async throws {
        let source = MosaicRuntimeSessionDriverInputProbe()
        let sink = MosaicRuntimeSessionDriverOutputProbe()
        let fixture = try MosaicRuntimeSessionDriverFixture.makeFixture(
            target: .bchSigning
        )
        let driver = try Driver(
            runtimeSession: fixture.session,
            dependencies: dependencies(source: source, sink: sink)
        )

        await driver.start()
        await source.waitUntilOpened()
        await source.send(
            .hostResult(
                .signedTransactionValidated(
                    attemptIdentifier: fixture.attemptIdentifier,
                    generationIdentifier: fixture.generationIdentifier,
                    contributorSigners: fixture.roster.contributors
                )
            )
        )
        await driver.waitForTermination()

        #expect(await source.closeCount == 1)
        #expect(sink.outputs.count == 2)
        #expect(sink.cancellationStates == [false, false])
        if case .runtimeEffect(
            .localAttempt(.walletReservationCommitRequired)
        ) = sink.outputs[0] {
            // Expected.
        } else {
            Issue.record("Expected wallet commit before completed termination")
        }
        #expect(
            sink.outputs[1]
                == .runtimeEffect(
                    .localAttempt(.attemptTerminated(.completed))
                )
        )
        #expect(await driver.state == .terminal(.completed))
    }

    private func makeDriver(
        target: MosaicRuntimeSessionDriverFixture.Target = .manifestAgreement,
        source: MosaicRuntimeSessionDriverInputProbe,
        sink: MosaicRuntimeSessionDriverOutputProbe
    ) throws -> Driver {
        try Driver(
            runtimeSession: MosaicRuntimeSessionDriverFixture.makeSession(
                target: target
            ),
            dependencies: dependencies(source: source, sink: sink)
        )
    }

    private func dependencies(
        source: MosaicRuntimeSessionDriverInputProbe,
        sink: MosaicRuntimeSessionDriverOutputProbe
    ) -> Driver.Dependencies {
        .init(
            openInputStream: {
                await source.open()
            },
            closeInputSource: {
                await source.close()
            },
            outputSink: { output in
                sink.record(output)
            }
        )
    }
}
