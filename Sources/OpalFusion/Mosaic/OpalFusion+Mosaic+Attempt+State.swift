// OpalFusion+Mosaic+Attempt+State.swift

extension OpalFusion.Mosaic.Attempt {
    enum Phase: Int, CaseIterable, Sendable, Equatable {
        case discovery
        case candidateSetAgreement
        case controlRosterAgreement
        case roleSelection
        case manifestAgreement
        case walletReservation
        case groupedCommitment
        case anonymousComponentSubmission
        case transcriptAgreement
        case bchSigning
    }

    enum Cancellation: Sendable, Equatable {
        case requested(during: Phase)
    }

    enum Outcome: Sendable, Equatable {
        case completed
        case failed(Failure)
        case cancelled(Cancellation)
    }

    enum State: Sendable, Equatable {
        case discovery
        case candidateSetAgreement(candidateCount: Int)
        case controlRosterAgreement(candidateCount: Int)
        case roleSelection(RoleSelectionState)
        case manifestAgreement(roleElection: RoleElectionResult)
        case walletReservation(roster: Roster, manifest: ManifestBinding)
        case groupedCommitment(roster: Roster, manifest: ManifestBinding)
        case anonymousComponentSubmission(
            roster: Roster,
            manifest: ManifestBinding,
            commitmentSet: CommitmentSetValidation
        )
        case transcriptAgreement(
            roster: Roster,
            transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
        )
        case bchSigning(
            roster: Roster,
            transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
        )
        case terminal(Outcome)

        var phase: Phase? {
            switch self {
            case .discovery:
                .discovery
            case .candidateSetAgreement:
                .candidateSetAgreement
            case .controlRosterAgreement:
                .controlRosterAgreement
            case .roleSelection:
                .roleSelection
            case .manifestAgreement:
                .manifestAgreement
            case .walletReservation:
                .walletReservation
            case .groupedCommitment:
                .groupedCommitment
            case .anonymousComponentSubmission:
                .anonymousComponentSubmission
            case .transcriptAgreement:
                .transcriptAgreement
            case .bchSigning:
                .bchSigning
            case .terminal:
                nil
            }
        }

        var reservationRoster: Roster? {
            switch self {
            case let .walletReservation(roster, _),
                 let .groupedCommitment(roster, _),
                 let .anonymousComponentSubmission(roster, _, _),
                 let .transcriptAgreement(roster, _),
                 let .bchSigning(roster, _):
                roster
            case .discovery, .candidateSetAgreement, .controlRosterAgreement,
                 .roleSelection, .manifestAgreement, .terminal:
                nil
            }
        }
    }
}
