// OpalFusion+Mosaic+OpalMainnetAlpha+PrivateDeploymentPolicy.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Frozen timing and admission-throttle values for the private deployment lane.
    ///
    /// The work threshold throttles admission only. It does not establish Sybil resistance.
    struct PrivateDeploymentPolicy: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case unalignedEpochStart(UInt64)
            case deadlineOverflow
        }

        static let frozen = Self()

        let discoveryEpochDurationSeconds: UInt64 = 300
        let minimumLeadingZeroWorkBitCount: UInt16 = 20

        private init() {}

        func epochStart(containing unixSeconds: UInt64) -> UInt64 {
            unixSeconds - unixSeconds % discoveryEpochDurationSeconds
        }

        func validate(epochStart: UInt64) throws(ValidationError) {
            guard epochStart % discoveryEpochDurationSeconds == 0 else {
                throw .unalignedEpochStart(epochStart)
            }
        }

        func preManifestDeadlines(
            forEpochStartingAt epochStart: UInt64
        ) throws(ValidationError) -> PreManifestDeadlineSchedule {
            try validate(epochStart: epochStart)
            return try .init(
                epochStart: epochStart,
                beaconCutoff: adding(60, to: epochStart),
                candidateSetAgreement: adding(90, to: epochStart),
                controlRosterAgreement: adding(120, to: epochStart),
                roleCommitment: adding(150, to: epochStart),
                roleReveal: adding(180, to: epochStart),
                manifestAgreement: adding(240, to: epochStart)
            )
        }

        func postManifestDeadlines(
            forPhaseStartingAt phaseStart: UInt64
        ) throws(ValidationError) -> DeadlineSchedule {
            let walletReservation = try adding(60, to: phaseStart)
            let groupedCommitment = try adding(120, to: phaseStart)
            let anonymousComponentSubmission = try adding(240, to: phaseStart)
            let transcriptAgreement = try adding(300, to: phaseStart)
            let bchSigning = try adding(360, to: phaseStart)
            do {
                return try .init(
                    phaseStart: phaseStart,
                    walletReservation: walletReservation,
                    groupedCommitment: groupedCommitment,
                    anonymousComponentSubmission: anonymousComponentSubmission,
                    transcriptAgreement: transcriptAgreement,
                    bchSigning: bchSigning
                )
            } catch {
                preconditionFailure("Frozen deadline offsets must remain strictly ordered.")
            }
        }

        func reservationLeaseExpirationUnixSeconds(
            for deadlines: DeadlineSchedule
        ) -> UInt64 {
            deadlines.bchSigning
        }

        private func adding(
            _ offset: UInt64,
            to base: UInt64
        ) throws(ValidationError) -> UInt64 {
            let result = base.addingReportingOverflow(offset)
            guard !result.overflow else { throw .deadlineOverflow }
            return result.partialValue
        }
    }
}
