// OpalFusionContractValidator+ValidationGroup1.swift

import OpalFusion
import Testing

extension OpalFusionContractValidator {
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
        let snapshot = await session.currentSnapshot

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

        let participantReservation = try await participantReservationSource.reserveParticipant(
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

    @Test("Host transaction finalization failures preserve typed public mappings")
    func validateTransactionFinalizationFailureConstruction() {
        let assemblyFailure = OpalFusion.Host.TransactionFinalizationFailure
            .transactionAssemblyFailed(summary: "Assembler could not build the transaction")
        let matchingAssemblyFailure = OpalFusion.Host.TransactionFinalizationFailure
            .transactionAssemblyFailed(summary: "Assembler could not build the transaction")
        let policyFailure = OpalFusion.Host.TransactionFinalizationFailure
            .hostPolicyRejected(summary: "Host policy rejected the transaction")

        #expect(assemblyFailure == matchingAssemblyFailure)
        #expect(assemblyFailure != policyFailure)
        #expect(assemblyFailure.summary == "Assembler could not build the transaction")
        #expect(assemblyFailure.clientError == .notImplemented)
        #expect(assemblyFailure.completionStatus == .hostRejected)
        #expect(policyFailure.summary == "Host policy rejected the transaction")
        #expect(policyFailure.clientError == .hostRejected)
        #expect(policyFailure.completionStatus == .hostRejected)
    }

    @Test("Host participant reservation failures preserve safe reason codes")
    func validateParticipantReservationFailureConstruction() {
        let unavailableFailure = OpalFusion.Host.ParticipantReservationFailure
            .reservationUnavailable(reason: .walletLocked, summary: "Wallet locked")
        let matchingUnavailableFailure = OpalFusion.Host.ParticipantReservationFailure
            .reservationUnavailable(reason: .walletLocked, summary: "Wallet locked")
        let policyFailure = OpalFusion.Host.ParticipantReservationFailure
            .hostPolicyRejected(reason: .noEligibleInputs, summary: "No eligible inputs")

        #expect(unavailableFailure == matchingUnavailableFailure)
        #expect(unavailableFailure != policyFailure)
        #expect(unavailableFailure.reason == .walletLocked)
        #expect(unavailableFailure.summary == "Wallet locked")
        #expect(unavailableFailure.clientError == .hostRejected)
        #expect(unavailableFailure.completionStatus == .hostRejected)
        #expect(policyFailure.reason == .noEligibleInputs)
        #expect(policyFailure.summary == "No eligible inputs")
        #expect(policyFailure.clientError == .hostRejected)
        #expect(policyFailure.completionStatus == .hostRejected)
    }

    @Test("Participant reservation context preserves coordinator round constraints")
    func validateParticipantReservationContextConstruction() {
        let roundIdentifier = OpalFusion.Round.Identifier(rawValue: "round-ctx")
        let context = OpalFusion.Host.ParticipantReservationContext(
            roundIdentifier: roundIdentifier,
            tierSatoshis: 10_000,
            numberOfComponents: 4,
            componentFeeRateSatoshisPerKb: 1_250,
            minimumExcessFeeSatoshis: 200,
            maximumExcessFeeSatoshis: 500
        )

        #expect(context.roundIdentifier == roundIdentifier)
        #expect(context.tierSatoshis == 10_000)
        #expect(context.numberOfComponents == 4)
        #expect(context.componentFeeRateSatoshisPerKb == 1_250)
        #expect(context.minimumExcessFeeSatoshis == 200)
        #expect(context.maximumExcessFeeSatoshis == 500)
    }
}
