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
        case roleSelection(controlIdentities: [ControlIdentity])
        case manifestAgreement(roster: Roster)
        case walletReservation(roster: Roster, manifest: ManifestIdentifier)
        case groupedCommitment(roster: Roster, manifest: ManifestIdentifier)
        case anonymousComponentSubmission(roster: Roster, manifest: ManifestIdentifier)
        case transcriptAgreement(roster: Roster, manifest: ManifestIdentifier)
        case bchSigning(
            roster: Roster,
            manifest: ManifestIdentifier,
            transcriptRoot: TranscriptRoot
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
                 let .anonymousComponentSubmission(roster, _),
                 let .transcriptAgreement(roster, _),
                 let .bchSigning(roster, _, _):
                roster
            case .discovery, .candidateSetAgreement, .controlRosterAgreement,
                 .roleSelection, .manifestAgreement, .terminal:
                nil
            }
        }
    }
}
