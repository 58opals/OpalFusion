// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestPhaseTag.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    static func postManifestRecoveryTag(
        for phase: OpalFusion.Mosaic.Attempt.Phase
    ) throws -> UInt8 {
        switch phase {
        case .walletReservation: 0
        case .groupedCommitment: 1
        case .anonymousComponentSubmission: 2
        case .transcriptAgreement: 3
        case .bchSigning: 4
        case .discovery, .candidateSetAgreement, .controlRosterAgreement,
             .roleSelection, .manifestAgreement:
            throw Failure.malformedRecoverySnapshot
        }
    }

    static func postManifestPhase(
        forRecoveryTag tag: UInt8
    ) throws -> OpalFusion.Mosaic.Attempt.Phase {
        switch tag {
        case 0: .walletReservation
        case 1: .groupedCommitment
        case 2: .anonymousComponentSubmission
        case 3: .transcriptAgreement
        case 4: .bchSigning
        default: throw Failure.malformedRecoverySnapshot
        }
    }
}
#endif
