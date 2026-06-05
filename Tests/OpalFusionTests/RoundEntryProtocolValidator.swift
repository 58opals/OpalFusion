// RoundEntryProtocolValidator.swift

import OpalFusion
import Testing

struct RoundEntryProtocolValidator {
    @Test("Round entry protocol models preserve fusion begin and start round values")
    func validateRoundEntryProtocolConstruction() {
        let fusionBegin = OpalFusion.ProtocolModel.FusionBegin(
            tier: 250_000,
            covertDomain: "covert.example.org",
            covertPort: 7447,
            covertSsl: true,
            serverTimeUnixSeconds: 1_712_345_678
        )
        let startRound = OpalFusion.ProtocolModel.StartRound(
            roundPublicKey: [0x11, 0x22, 0x33],
            blindNoncePoints: [
                [0xAA, 0xBB],
                [0xCC, 0xDD]
            ],
            serverTimeUnixSeconds: 1_712_345_690
        )
        let restartRound = OpalFusion.ProtocolModel.RestartRound()
        let serverFailure = OpalFusion.ProtocolModel.ServerFailure(
            message: "protocol mismatch"
        )

        #expect(fusionBegin.tier == 250_000)
        #expect(fusionBegin.covertDomain == "covert.example.org")
        #expect(fusionBegin.covertPort == 7447)
        #expect(fusionBegin.covertSsl == true)
        #expect(fusionBegin.serverTimeUnixSeconds == 1_712_345_678)
        #expect(startRound.roundPublicKey == [0x11, 0x22, 0x33])
        #expect(startRound.blindNoncePoints == [[0xAA, 0xBB], [0xCC, 0xDD]])
        #expect(startRound.serverTimeUnixSeconds == 1_712_345_690)
        #expect(restartRound == .init())
        #expect(serverFailure.message == "protocol mismatch")
    }

    @Test("Server failure identifiers avoid substring false positives")
    func validateServerFailureIdentifierTokenMatching() {
        let fulfilledFailure = OpalFusion.ProtocolModel.ServerFailure(
            message: "Coordinator fulfilled request before rejecting follow-up"
        )
        let joinPoolsFailure = OpalFusion.ProtocolModel.ServerFailure(
            message: "Coordinator rejected JoinPools"
        )

        #expect(fulfilledFailure.sanitizedProtocolErrorIdentifier == "server_failure_coordinator_rejected")
        #expect(joinPoolsFailure.sanitizedProtocolErrorIdentifier == "server_failure_join_rejected")
    }
}
