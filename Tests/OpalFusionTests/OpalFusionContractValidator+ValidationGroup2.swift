// OpalFusionContractValidator+ValidationGroup2.swift

import OpalFusion
import Testing

extension OpalFusionContractValidator {
    @Test("Round-identifier reservation sources work through the context default")
    func validateParticipantReservationContextDefaultSourceCompatibility() async throws {
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "round-default")
        let reservation = OpalFusion.Host.ParticipantReservation(
            inputs: [
                .init(
                    outpointTransactionHashBytes: [0xBA, 0x5E],
                    outpointIndex: 1,
                    amountSatoshis: 30_000,
                    lockingScriptBytes: [0x51]
                )
            ],
            outputs: [
                .init(
                    lockingScriptBytes: [0x76, 0xA9, 0x14, 0x02, 0x88, 0xAC],
                    amountSatoshis: 29_000
                )
            ]
        )
        let context = OpalFusion.Host.ParticipantReservationContext(
            roundIdentifier: roundIdentifier,
            tierSatoshis: 10_000,
            numberOfComponents: 4,
            componentFeeRateSatoshisPerKb: 1_000,
            minimumExcessFeeSatoshis: 200,
            maximumExcessFeeSatoshis: 500
        )
        let source = RoundIdentifierOnlyParticipantReservationSource(
            reservation: reservation
        )
        let participantReservationSource: any OpalFusion.Host.ParticipantReservationSource = source

        let loadedReservation = try await participantReservationSource.reserveParticipant(
            for: context
        )

        #expect(loadedReservation == reservation)
        #expect(await source.requestedRounds == [roundIdentifier])
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

    @Test("Client session snapshot preserves state and coordinator status")
    func validateClientSessionSnapshotConstruction() {
        let state = OpalFusion.Client.State(
            isConnected: true,
            round: .init(
                identifier: .init(rawValue: "round-003"),
                completionStatus: .success
            )
        )
        let coordinatorStatus = OpalFusion.Client.Session.Snapshot.CoordinatorStatus(
            updateSequence: 2,
            latestInboundMessageKind: "TierStatusUpdate",
            latestInboundPayloadByteCount: 24,
            queueStatus: .init(
                tierSatoshis: 10_000,
                players: 3,
                minPlayers: 2,
                maxPlayers: 8,
                timeRemaining: 17
            )
        )
        let snapshot = OpalFusion.Client.Session.Snapshot(
            state: state,
            lastError: .transportUnavailable,
            lastErrorSummary: "Primary connection failed",
            coordinatorStatus: coordinatorStatus
        )

        #expect(snapshot.state == state)
        #expect(snapshot.lastError == .transportUnavailable)
        #expect(snapshot.lastErrorSummary == "Primary connection failed")
        #expect(snapshot.coordinatorStatus == coordinatorStatus)
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
