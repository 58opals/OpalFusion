// OpalFusion+Runtime+LiveRuntimeDriver+HostOperation.swift

extension OpalFusion.Runtime.LiveRuntimeDriver {
    func requestParticipantReservation(
        _ context: OpalFusion.Host.ParticipantReservationContext
    ) {
        let participantReservationSource = self.participantReservationSource
        let roundIdentifier = context.roundIdentifier
        participantReservationTask?.cancel()
        participantReservationTask = Task { [participantReservationSource] in
            do {
                let reservation = try await participantReservationSource.reserveParticipant(
                    for: context
                )
                guard Task.isCancelled == false else {
                    return
                }
                await self.handleHostOperationIfCurrent(
                    roundIdentifier: roundIdentifier,
                    staleOperation: "participant reservation",
                    input: .participantReservationLoaded(reservation)
                )
            } catch let failure as OpalFusion.Host.ParticipantReservationFailure {
                guard Task.isCancelled == false else {
                    return
                }
                await self.handleHostOperationIfCurrent(
                    roundIdentifier: roundIdentifier,
                    staleOperation: "participant reservation rejection",
                    input: .participantReservationRejected(failure)
                )
            } catch {
                guard Task.isCancelled == false else {
                    return
                }
                await self.handleHostOperationIfCurrent(
                    roundIdentifier: roundIdentifier,
                    staleOperation: "participant reservation rejection",
                    input: .participantReservationRejected(
                        .reservationUnavailable(
                            reason: .unknown,
                            summary: "Host participant reservation failed"
                        )
                    )
                )
            }
        }
    }

    func requestTransactionFinalization(
        roundIdentifier: OpalFusion.Round.Identifier,
        proposal: OpalFusion.Host.TransactionFinalizationProposal
    ) {
        let transactionAssembler = self.transactionAssembler
        transactionFinalizationTask?.cancel()
        transactionFinalizationTask = Task { [transactionAssembler] in
            do {
                let transaction = try await transactionAssembler.finalizeFusionTransaction(
                    for: roundIdentifier,
                    proposal: proposal
                )
                guard Task.isCancelled == false else {
                    return
                }
                await self.handleHostOperationIfCurrent(
                    roundIdentifier: roundIdentifier,
                    staleOperation: "transaction finalization",
                    input: .finalizedTransactionLoaded(transaction)
                )
            } catch let failure as OpalFusion.Host.TransactionFinalizationFailure {
                guard Task.isCancelled == false else {
                    return
                }
                await self.handleHostOperationIfCurrent(
                    roundIdentifier: roundIdentifier,
                    staleOperation: "transaction finalization rejection",
                    input: .transactionFinalizationRejected(failure)
                )
            } catch {
                guard Task.isCancelled == false else {
                    return
                }
                await self.handleHostOperationIfCurrent(
                    roundIdentifier: roundIdentifier,
                    staleOperation: "transaction finalization rejection",
                    input: .transactionFinalizationRejected(
                        .transactionAssemblyFailed(
                            summary: "Host transaction finalization failed"
                        )
                    )
                )
            }
        }
    }
}
