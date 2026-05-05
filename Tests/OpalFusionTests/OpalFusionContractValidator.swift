// OpalFusionContractValidator.swift

import OpalFusion
import Testing

struct OpalFusionContractValidator {
    @Test("Public scaffold types remain constructible from the documented example")
    func validatePublicScaffoldConstruction() async {
        let covertChannel = OpalFusion.Transport.CovertChannelConfiguration(
            entryPath: "/fusion",
            maxPayloadBytes: 32_768,
            requestTimeoutMilliseconds: 15_000
        )
        let configuration = OpalFusion.Client.Configuration(
            coordinatorHost: "fusion.example.org",
            coordinatorPort: 8787,
            covertChannel: covertChannel
        )
        let round = OpalFusion.Round.State(
            identifier: .init(rawValue: "round-001"),
            phase: .connecting
        )
        let state = OpalFusion.Client.State(
            isConnected: false,
            round: round
        )
        let session = OpalFusion.Client.Session(
            configuration: configuration,
            joinPools: .init(tiers: [10_000], tags: []),
            participantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: []
            ),
            transactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: .init(transactionBytes: [])
            )
        )
        let snapshot = await session.snapshot()

        #expect(configuration.coordinatorHost == "fusion.example.org")
        #expect(configuration.coordinatorPort == 8787)
        #expect(configuration.coordinatorRequiresTLS == false)
        #expect(configuration.covertChannel == covertChannel)
        #expect(configuration.torSocks5 == nil)
        #expect(state.isConnected == false)
        #expect(state.round == round)
        #expect(snapshot == .init())
    }

    @Test("Round state remains constructible with an additive completion status")
    func validateRoundStateCompletionStatusConstruction() {
        let round = OpalFusion.Round.State(
            identifier: .init(rawValue: "round-002"),
            participantCount: 8,
            completionStatus: .success
        )

        #expect(round.identifier == .init(rawValue: "round-002"))
        #expect(round.phase == .completed)
        #expect(round.participantCount == 8)
        #expect(round.completionStatus == .success)
        #expect(round.isTerminal == true)
    }

    @Test("Host protocol adapters satisfy the public host integration seams")
    func validateHostProtocolAdapters() async throws {
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "round-001")
        let participantInput = OpalFusion.Host.ParticipantInput(
            outpointTransactionHashBytes: [0x00, 0x01],
            outpointIndex: 1,
            amountSatoshis: 42_000,
            lockingScriptBytes: [0x51]
        )
        let participantOutput = OpalFusion.Host.ParticipantOutput(
            lockingScriptBytes: [0x76, 0xA9, 0x14, 0x01, 0x88, 0xAC],
            amountSatoshis: 41_000
        )
        let reservation = OpalFusion.Host.ParticipantReservation(
            inputs: [participantInput],
            outputs: [participantOutput]
        )
        let finalizedTransaction = OpalFusion.Host.FinalizedTransaction(
            transactionBytes: [0xDE, 0xAD, 0xBE, 0xEF]
        )
        let proposal = OpalFusion.Host.TransactionFinalizationProposal(
            unsignedTransactionBytes: [0xAA]
        )
        let event = OpalFusion.Host.Event(
            kind: .completed,
            phase: .completed,
            summary: "Round completed",
            isTerminal: true
        )

        let participantReservationSource: any OpalFusion.Host.ParticipantReservationSource =
            HostParticipantReservationSourceAdapter(
                participantInputs: [participantInput],
                participantOutputs: [participantOutput]
            )
        let transactionAssembler: any OpalFusion.Host.TransactionAssembler =
            HostTransactionAssemblerAdapter(finalizedTransaction: finalizedTransaction)
        let eventObserver: any OpalFusion.Host.EventObserver = HostEventObserverAdapter()

        let participantReservation = try await participantReservationSource.participantReservation(
            for: roundIdentifier
        )
        let assembledTransaction = try await transactionAssembler.finalizeTransaction(
            for: roundIdentifier,
            proposal: proposal
        )
        await eventObserver.receive(event, for: roundIdentifier)

        #expect(participantReservation == reservation)
        #expect(participantReservation.inputs == [participantInput])
        #expect(participantReservation.outputs == [participantOutput])
        #expect(assembledTransaction == finalizedTransaction)
    }

    @Test("Participant input preserves the additive optional public key")
    func validateParticipantInputPublicKeyConstruction() {
        let legacyInput = OpalFusion.Host.ParticipantInput(
            outpointTransactionHashBytes: [0x00, 0x01],
            outpointIndex: 1,
            amountSatoshis: 42_000,
            lockingScriptBytes: [0x51]
        )
        let enrichedInput = OpalFusion.Host.ParticipantInput(
            outpointTransactionHashBytes: [0x02, 0x03],
            outpointIndex: 2,
            amountSatoshis: 84_000,
            lockingScriptBytes: [0x52],
            publicKey: [0x02, 0xAA, 0xBB]
        )

        #expect(legacyInput.publicKey == nil)
        #expect(enrichedInput.publicKey == [0x02, 0xAA, 0xBB])
    }

    @Test("Participant reservation keeps additive host output modeling source-compatible")
    func validateParticipantReservationConstruction() {
        let output = OpalFusion.Host.ParticipantOutput(
            lockingScriptBytes: [0x76, 0xA9, 0x14, 0x02, 0x88, 0xAC],
            amountSatoshis: 21_000
        )
        let reservation = OpalFusion.Host.ParticipantReservation(
            inputs: [
                .init(
                    outpointTransactionHashBytes: [0xAA, 0xBB],
                    outpointIndex: 0,
                    amountSatoshis: 22_000,
                    lockingScriptBytes: [0x51],
                    publicKey: [0x02, 0x11, 0x22]
                )
            ],
            outputs: [output]
        )

        #expect(reservation.inputs.count == 1)
        #expect(reservation.outputs == [output])
    }

    @Test("Client session snapshot preserves state and diagnostics visibility")
    func validateClientSessionSnapshotConstruction() {
        let state = OpalFusion.Client.State(
            isConnected: true,
            round: .init(
                identifier: .init(rawValue: "round-003"),
                completionStatus: .success
            )
        )
        let snapshot = OpalFusion.Client.Session.Snapshot(
            state: state,
            lastError: .transportUnavailable,
            lastErrorSummary: "Primary connection failed",
            diagnostics: .init(
                activity: .retrying,
                retryAttempt: 1,
                nextRetryDelayMilliseconds: 3_000,
                primaryFailureCategory: .transportUnavailable,
                primaryFailureSummary: "Primary connection failed",
                handshakeStage: .awaitingServerHello,
                recentEvents: [
                    .init(
                        kind: .retry,
                        summary: "Primary reconnect scheduled",
                        retryAttempt: 1,
                        retryDelayMilliseconds: 3_000,
                        handshakeStage: .awaitingServerHello
                    )
                ]
            )
        )

        #expect(snapshot.state == state)
        #expect(snapshot.lastError == .transportUnavailable)
        #expect(snapshot.lastErrorSummary == "Primary connection failed")
        #expect(snapshot.diagnostics.activity == .retrying)
        #expect(snapshot.diagnostics.retryAttempt == 1)
        #expect(snapshot.diagnostics.nextRetryDelayMilliseconds == 3_000)
        #expect(snapshot.diagnostics.primaryFailureCategory == .transportUnavailable)
        #expect(snapshot.diagnostics.handshakeStage == .awaitingServerHello)
        #expect(snapshot.diagnostics.recentEvents.count == 1)
    }

    @Test("Client reconnect policy exposes disabled and wallet defaults")
    func validateClientReconnectPolicyDefaults() {
        let disabled = OpalFusion.Client.ReconnectPolicy.disabled
        #expect(disabled.maximumAttempts == 0)

        let walletDefault = OpalFusion.Client.ReconnectPolicy.walletDefault
        #expect(walletDefault.initialDelay == .seconds(3))
        #expect(walletDefault.maximumDelay == .seconds(30))
        #expect(walletDefault.multiplier == 1.5)
        #expect(walletDefault.maximumAttempts == nil)
    }

    @Test("Client state observer satisfies the public session observation seam")
    func validateClientStateObserverAdapter() async {
        let observer: any OpalFusion.Client.StateObserver = ClientStateObserverAdapter()
        let snapshot = OpalFusion.Client.Session.Snapshot(
            state: .init(isConnected: true),
            lastError: nil,
            lastErrorSummary: nil
        )

        await observer.receive(snapshot)
        #expect(snapshot.state.isConnected)
        #expect(snapshot.lastError == nil)
        #expect(snapshot.lastErrorSummary == nil)
    }
}
