// OpalFusionContractValidator.swift

import OpalFusion
import Testing

struct OpalFusionContractValidator {
    @Test("Public scaffold types remain constructible from the documented example")
    func validatePublicScaffoldConstruction() {
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

        #expect(configuration.coordinatorHost == "fusion.example.org")
        #expect(configuration.coordinatorPort == 8787)
        #expect(configuration.covertChannel == covertChannel)
        #expect(configuration.torSocks5 == nil)
        #expect(state.isConnected == false)
        #expect(state.round == round)
    }

    @Test("Round state remains constructible with an additive completion status")
    func validateRoundStateCompletionStatusConstruction() {
        let round = OpalFusion.Round.State(
            identifier: .init(rawValue: "round-002"),
            phase: .completed,
            participantCount: 8,
            completionStatus: .success,
            isTerminal: true
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
            outpointTransactionHash: [0x00, 0x01],
            outpointIndex: 1,
            amountSatoshis: 42_000,
            lockingScript: [0x51]
        )
        let participantOutput = OpalFusion.Host.ParticipantOutput(
            lockingScript: [0x76, 0xA9, 0x14, 0x01, 0x88, 0xAC],
            amountSatoshis: 41_000
        )
        let reservation = OpalFusion.Host.ParticipantReservation(
            inputs: [participantInput],
            outputs: [participantOutput]
        )
        let finalizedTransaction = OpalFusion.Host.FinalizedTransaction(
            serializedTransaction: [0xDE, 0xAD, 0xBE, 0xEF]
        )
        let proposal = OpalFusion.Host.TransactionFinalizationProposal(
            serializedUnsignedTransaction: [0xAA]
        )
        let event = OpalFusion.Host.Event(
            kind: .completed,
            phase: .completed,
            summary: "Round completed",
            isTerminal: true
        )

        let inputProvider: any OpalFusion.Host.ParticipantInputProvider =
            HostParticipantInputProviderAdapter(
                participantInputs: [participantInput],
                participantOutputs: [participantOutput]
            )
        let transactionAssembler: any OpalFusion.Host.TransactionAssembler =
            HostTransactionAssemblerAdapter(finalizedTransaction: finalizedTransaction)
        let eventObserver: any OpalFusion.Host.EventObserver = HostEventObserverAdapter()

        let reservedInputs = try await inputProvider.reservedInputs(for: roundIdentifier)
        let participantReservation = try await inputProvider.participantReservation(
            for: roundIdentifier
        )
        let assembledTransaction = try await transactionAssembler.finalizeTransaction(
            for: roundIdentifier,
            proposal: proposal
        )
        await eventObserver.receive(event, for: roundIdentifier)

        #expect(reservedInputs == [participantInput])
        #expect(participantReservation == reservation)
        #expect(assembledTransaction == finalizedTransaction)
    }

    @Test("Participant input preserves the additive optional public key")
    func validateParticipantInputPublicKeyConstruction() {
        let legacyInput = OpalFusion.Host.ParticipantInput(
            outpointTransactionHash: [0x00, 0x01],
            outpointIndex: 1,
            amountSatoshis: 42_000,
            lockingScript: [0x51]
        )
        let enrichedInput = OpalFusion.Host.ParticipantInput(
            outpointTransactionHash: [0x02, 0x03],
            outpointIndex: 2,
            amountSatoshis: 84_000,
            lockingScript: [0x52],
            publicKey: [0x02, 0xAA, 0xBB]
        )

        #expect(legacyInput.publicKey == nil)
        #expect(enrichedInput.publicKey == [0x02, 0xAA, 0xBB])
    }

    @Test("Participant reservation keeps additive host output modeling source-compatible")
    func validateParticipantReservationConstruction() {
        let output = OpalFusion.Host.ParticipantOutput(
            lockingScript: [0x76, 0xA9, 0x14, 0x02, 0x88, 0xAC],
            amountSatoshis: 21_000
        )
        let reservation = OpalFusion.Host.ParticipantReservation(
            inputs: [
                .init(
                    outpointTransactionHash: [0xAA, 0xBB],
                    outpointIndex: 0,
                    amountSatoshis: 22_000,
                    lockingScript: [0x51],
                    publicKey: [0x02, 0x11, 0x22]
                )
            ],
            outputs: [output]
        )

        #expect(reservation.inputs.count == 1)
        #expect(reservation.outputs == [output])
    }

    @Test("ParticipantInputProvider default reservation preserves legacy input-only conformers")
    func validateParticipantReservationDefaultImplementation() async throws {
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "round-legacy")
        let participantInput = OpalFusion.Host.ParticipantInput(
            outpointTransactionHash: [0x01, 0x02],
            outpointIndex: 0,
            amountSatoshis: 1_000,
            lockingScript: [0x51]
        )
        let provider: any OpalFusion.Host.ParticipantInputProvider =
            LegacyParticipantInputProvider(participantInputs: [participantInput])

        let reservation = try await provider.participantReservation(for: roundIdentifier)

        #expect(reservation.inputs == [participantInput])
        #expect(reservation.outputs.isEmpty)
    }
}

private struct LegacyParticipantInputProvider: OpalFusion.Host.ParticipantInputProvider {
    let participantInputs: [OpalFusion.Host.ParticipantInput]

    func reservedInputs(
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async throws -> [OpalFusion.Host.ParticipantInput] {
        participantInputs
    }
}
