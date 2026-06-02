// PrimaryRuntimeSessionValidator+ValidationGroup2.swift

@testable import OpalFusion
import Testing

extension PrimaryRuntimeSessionValidator {
    @Test("Primary runtime drives framed StartRound input collection and PlayerCommit submission")
    func validateStartRoundAndCommitFlow() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveThroughWarmup(session: &session)

        let requestEffects = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .startRound(PrimaryRuntimeTestFixtures.startRound)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_030)
        )

        #expect(
            requestEffects == [
                .requestParticipantReservation(
                    context: PrimaryRuntimeTestFixtures.participantReservationContext
                ),
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .registeringInputs,
                        summary: "StartRound received; collecting reserved inputs and outputs"
                    )
                )
            ]
        )
        #expect(
            session.clientState.round == .init(
                identifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                phase: .registeringInputs
            )
        )

        let commitEffects = session.apply(
            input: .participantReservationLoaded(
                PrimaryRuntimeTestFixtures.participantReservation
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_031)
        )
        #expect(commitEffects.count == 2)
        let commitWriteEffect = try #require(commitEffects.first)
        #expect(
            try PrimaryRuntimeTestFixtures.extractWriteMessage(from: commitWriteEffect)
                == .playerCommit(PrimaryRuntimeTestFixtures.playerCommit)
        )
        let commitEventEffect = try #require(commitEffects.dropFirst().first)
        #expect(
            commitEventEffect == .emitHostEvent(
                roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                event: .init(
                    kind: .status,
                    phase: .awaitingBlindSignatures,
                    summary: "Submitting player commitments and blind requests"
                )
            )
        )
        #expect(session.clientState.round?.phase == .awaitingBlindSignatures)
    }

    @Test("Primary runtime handles fragmented inbound frames without losing state projection")
    func validateFragmentedInboundFlow() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        _ = session.apply(input: .connected, now: PrimaryRuntimeTestFixtures.instant(995))

        let serverHelloFrame = try PrimaryRuntimeTestFixtures.encodeServerFrame(
            .serverHello(PrimaryRuntimeTestFixtures.serverHello)
        )
        let serverHelloSplit = serverHelloFrame.count / 2
        #expect(
            session.apply(
                input: .receivedPrimaryBytes(Array(serverHelloFrame[..<serverHelloSplit])),
                now: PrimaryRuntimeTestFixtures.instant(996)
            )
                .isEmpty
        )
        let helloEffects = session.apply(
            input: .receivedPrimaryBytes(Array(serverHelloFrame[serverHelloSplit...])),
            now: PrimaryRuntimeTestFixtures.instant(996)
        )
        let helloEffect = try #require(helloEffects.first)
        #expect(
            try PrimaryRuntimeTestFixtures.extractWriteMessage(from: helloEffect)
                == .joinPools(PrimaryRuntimeTestFixtures.joinPools)
        )

        _ = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )

        let startRoundFrame = try PrimaryRuntimeTestFixtures.encodeServerFrame(
            .startRound(PrimaryRuntimeTestFixtures.startRound)
        )
        let firstCut = startRoundFrame.count / 3
        let secondCut = (startRoundFrame.count * 2) / 3

        #expect(
            session.apply(
                input: .receivedPrimaryBytes(Array(startRoundFrame[..<firstCut])),
                now: PrimaryRuntimeTestFixtures.instant(1_030)
            )
                .isEmpty
        )
        #expect(session.clientState.round == nil)
        #expect(
            session.apply(
                input: .receivedPrimaryBytes(Array(startRoundFrame[firstCut..<secondCut])),
                now: PrimaryRuntimeTestFixtures.instant(1_030)
            )
                .isEmpty
        )
        #expect(session.clientState.round == nil)

        let startRoundEffects = session.apply(
            input: .receivedPrimaryBytes(Array(startRoundFrame[secondCut...])),
            now: PrimaryRuntimeTestFixtures.instant(1_030)
        )
        #expect(
            startRoundEffects == [
                .requestParticipantReservation(
                    context: PrimaryRuntimeTestFixtures.participantReservationContext
                ),
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .registeringInputs,
                        summary: "StartRound received; collecting reserved inputs and outputs"
                    )
                )
            ]
        )
        #expect(
            session.clientState.round == .init(
                identifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                phase: .registeringInputs
            )
        )
    }
}
