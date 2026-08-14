// OpalFusion+Mosaic+OpalMainnetAlpha+PreManifestDeadlineSchedule.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Unix-second boundaries for one aligned private-deployment discovery epoch.
    struct PreManifestDeadlineSchedule: Sendable, Equatable {
        let epochStart: UInt64
        let beaconCutoff: UInt64
        let candidateSetAgreement: UInt64
        let controlRosterAgreement: UInt64
        let roleCommitment: UInt64
        let roleReveal: UInt64
        let manifestAgreement: UInt64

        init(
            epochStart: UInt64,
            beaconCutoff: UInt64,
            candidateSetAgreement: UInt64,
            controlRosterAgreement: UInt64,
            roleCommitment: UInt64,
            roleReveal: UInt64,
            manifestAgreement: UInt64
        ) {
            self.epochStart = epochStart
            self.beaconCutoff = beaconCutoff
            self.candidateSetAgreement = candidateSetAgreement
            self.controlRosterAgreement = controlRosterAgreement
            self.roleCommitment = roleCommitment
            self.roleReveal = roleReveal
            self.manifestAgreement = manifestAgreement
        }
    }
}
