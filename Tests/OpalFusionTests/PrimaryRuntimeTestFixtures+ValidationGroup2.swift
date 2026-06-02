// PrimaryRuntimeTestFixtures+ValidationGroup2.swift

@testable import OpalFusion

extension PrimaryRuntimeTestFixtures {
    static func driveToAwaitingResult(
        session: inout OpalFusion.Runtime.PrimaryRuntimeSession
    ) throws {
        try driveToAwaitingSharedComponents(session: &session)
        _ = session.apply(
            input: .receivedPrimaryBytes(
                try encodeServerFrame(.shareCovertComponents(sharedComponents))
            ),
            now: instant(1_040)
        )
        _ = session.apply(
            input: .finalizedTransactionLoaded(finalizedTransaction),
            now: instant(1_042)
        )
        _ = session.apply(
            input: .clockAdvanced,
            now: instant(1_050)
        )
        _ = session.apply(
            input: .receivedCovertResponseBytes(
                try encodeCovertResponsePayload(acknowledgement)
            ),
            now: instant(1_051)
        )
    }

    static func driveToAwaitingRestart(
        session: inout OpalFusion.Runtime.PrimaryRuntimeSession
    ) throws {
        try driveToAwaitingResult(session: &session)
        _ = session.apply(
            input: .receivedPrimaryBytes(
                try encodeServerFrame(.fusionResult(failureResult))
            ),
            now: instant(1_055)
        )
        _ = session.apply(
            input: .receivedPrimaryBytes(
                try encodeServerFrame(.theirProofsList(theirProofsList))
            ),
            now: instant(1_056)
        )
    }
}
