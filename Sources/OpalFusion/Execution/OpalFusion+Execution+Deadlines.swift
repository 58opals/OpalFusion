// OpalFusion+Execution+Deadlines.swift

import OpalCrypto

extension OpalFusion.Execution {
    struct Deadlines: Sendable, Equatable {
        let fusionBeginAt: OpalFusion.Execution.Instant
        let warmupTarget: OpalFusion.Execution.Instant
        let warmupDeadline: OpalFusion.Execution.Instant
        let roundStartAt: OpalFusion.Execution.Instant?
        let commitmentsDeadline: OpalFusion.Execution.Instant?
        let covertComponentsStart: OpalFusion.Execution.Instant?
        let covertComponentsDeadline: OpalFusion.Execution.Instant?
        let signaturesStart: OpalFusion.Execution.Instant?
        let signaturesDeadline: OpalFusion.Execution.Instant?
        let conclusionTimeout: OpalFusion.Execution.Instant?
        let closeStart: OpalFusion.Execution.Instant?
        let blameCloseStart: OpalFusion.Execution.Instant?
        let blameVerifyDeadline: OpalFusion.Execution.Instant?

        static func fromFusionBegin(
            _ fusionBegin: OpalFusion.ProtocolModel.FusionBegin,
            timing: OpalFusion.Transport.RoundTimingConfiguration
        ) -> Self {
            let fusionBeginAt = OpalFusion.Execution.Instant(unixSeconds: fusionBegin.serverTimeUnixSeconds)
            let warmupTarget = fusionBeginAt.advanced(by: timing.warmupDuration)
            return .init(
                fusionBeginAt: fusionBeginAt,
                warmupTarget: warmupTarget,
                warmupDeadline: warmupTarget.advanced(by: timing.warmupSlop),
                roundStartAt: nil,
                commitmentsDeadline: nil,
                covertComponentsStart: nil,
                covertComponentsDeadline: nil,
                signaturesStart: nil,
                signaturesDeadline: nil,
                conclusionTimeout: nil,
                closeStart: nil,
                blameCloseStart: nil,
                blameVerifyDeadline: nil
            )
        }

        func withStartRound(
            _ startRound: OpalFusion.ProtocolModel.StartRound,
            timing: OpalFusion.Transport.RoundTimingConfiguration
        ) -> Self {
            let roundStartAt = OpalFusion.Execution.Instant(unixSeconds: startRound.serverTimeUnixSeconds)
            let blameCloseStart = roundStartAt.advanced(by: timing.blameCloseStartFromRoundStart)
            return .init(
                fusionBeginAt: fusionBeginAt,
                warmupTarget: warmupTarget,
                warmupDeadline: warmupDeadline,
                roundStartAt: roundStartAt,
                commitmentsDeadline: roundStartAt.advanced(by: timing.commitmentsDeadlineFromRoundStart),
                covertComponentsStart: roundStartAt.advanced(by: timing.covertComponentsStartFromRoundStart),
                covertComponentsDeadline: roundStartAt.advanced(by: timing.covertComponentsDeadlineFromRoundStart),
                signaturesStart: roundStartAt.advanced(by: timing.signaturesStartFromRoundStart),
                signaturesDeadline: roundStartAt.advanced(by: timing.signaturesDeadlineFromRoundStart),
                conclusionTimeout: roundStartAt.advanced(by: timing.conclusionTimeoutFromRoundStart),
                closeStart: roundStartAt.advanced(by: timing.closeStartFromRoundStart),
                blameCloseStart: blameCloseStart,
                blameVerifyDeadline: blameCloseStart.advanced(by: timing.blameVerifyDuration)
            )
        }
    }
}
