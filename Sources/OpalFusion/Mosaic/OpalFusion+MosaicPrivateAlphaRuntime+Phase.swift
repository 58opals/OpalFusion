// OpalFusion+MosaicPrivateAlphaRuntime+Phase.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public enum Phase: CaseIterable, Sendable {
        case discovery
        case candidateSetAgreement
        case admission
        case controlRosterAgreement
        case roleElection
        case nonceAllocation
        case manifestAgreement
        case walletReservation
        case groupedCommitment
        case anonymousComponentSubmission
        case transcriptAgreement
        case bchSigning
    }
}

extension OpalFusion.MosaicPrivateAlphaRuntime.Phase {
    init?(recoveryTag: UInt8) {
        guard let phase = Self.allCases.first(where: {
            $0.recoveryTag == recoveryTag
        }) else {
            return nil
        }
        self = phase
    }

    var recoveryTag: UInt8 {
        switch self {
        case .discovery: 0
        case .candidateSetAgreement: 1
        case .admission: 2
        case .controlRosterAgreement: 3
        case .roleElection: 4
        case .nonceAllocation: 5
        case .manifestAgreement: 6
        case .walletReservation: 7
        case .groupedCommitment: 8
        case .anonymousComponentSubmission: 9
        case .transcriptAgreement: 10
        case .bchSigning: 11
        }
    }

    var isPreManifest: Bool {
        switch self {
        case .discovery, .candidateSetAgreement, .admission,
             .controlRosterAgreement, .roleElection, .nonceAllocation,
             .manifestAgreement:
            true
        case .walletReservation, .groupedCommitment,
             .anonymousComponentSubmission, .transcriptAgreement, .bchSigning:
            false
        }
    }
}
#endif
