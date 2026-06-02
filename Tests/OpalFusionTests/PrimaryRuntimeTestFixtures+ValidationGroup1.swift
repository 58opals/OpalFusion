// PrimaryRuntimeTestFixtures+ValidationGroup1.swift

@testable import OpalFusion

extension PrimaryRuntimeTestFixtures {
    static func makeSession(
        baseline: OpalFusion.Transport.BaselineConfiguration = PrimaryRuntimeTestFixtures.baseline
    ) -> OpalFusion.Runtime.PrimaryRuntimeSession {
        .init(
            configuration: configuration,
            genesisHash: clientHello.genesisHash,
            joinPools: joinPools,
            workflow: workflow,
            baseline: baseline
        )
    }

    static func makeCovertSession() -> OpalFusion.Runtime.CovertRuntimeSession {
        .init()
    }

    static func instant(_ unixSeconds: UInt64) -> OpalFusion.Execution.Instant {
        .init(unixSeconds: unixSeconds)
    }

    static func encodeServerPayload(
        _ message: OpalFusion.ProtocolModel.ServerMessage
    ) throws -> [UInt8] {
        try OpalFusion.Wire.PrimaryMessageEncoder().encode(message)
    }

    static func encodeServerFrame(
        _ message: OpalFusion.ProtocolModel.ServerMessage
    ) throws -> [UInt8] {
        try OpalFusion.Wire.PrimaryFrameEncoder(configuration: baseline.framing)
            .encode(payload: encodeServerPayload(message))
    }

    static func encodeCovertMessagePayload(
        _ message: OpalFusion.ProtocolModel.CovertMessage
    ) throws -> [UInt8] {
        try OpalFusion.Wire.CovertMessageEncoder().encode(message)
    }

    static func encodeCovertResponsePayload(
        _ response: OpalFusion.ProtocolModel.CovertResponse
    ) throws -> [UInt8] {
        try OpalFusion.Wire.CovertMessageEncoder().encode(response)
    }

    static func decodeClientMessage(
        from framedBytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.ClientMessage {
        var frameDecoder = OpalFusion.Wire.PrimaryFrameDecoder(configuration: baseline.framing)
        let payloads = try frameDecoder.append(framedBytes)
        guard payloads.count == 1 else {
            throw PrimaryRuntimeTestFixtureError.expectedSinglePayload(payloads.count)
        }
        return try OpalFusion.Wire.PrimaryMessageDecoder().decodeClient(payloads[0])
    }

    static func extractWriteMessage(
        from effect: OpalFusion.Runtime.PrimaryRuntimeSession.Effect
    ) throws -> OpalFusion.ProtocolModel.ClientMessage {
        guard case let .writePrimaryBytes(bytes) = effect else {
            throw PrimaryRuntimeTestFixtureError.expectedWriteEffect
        }
        return try decodeClientMessage(from: bytes)
    }

    static func extractCovertMessage(
        from request: OpalFusion.Runtime.CovertRequest
    ) throws -> OpalFusion.ProtocolModel.CovertMessage {
        try OpalFusion.Wire.CovertMessageDecoder().decodeMessage(request.payload)
    }

    static func extractCovertRequest(
        from effect: OpalFusion.Runtime.PrimaryRuntimeSession.Effect
    ) throws -> OpalFusion.Runtime.CovertRequest {
        guard case let .performCovertRequest(request) = effect else {
            throw PrimaryRuntimeTestFixtureError.expectedCovertRequestEffect
        }
        return request
    }

    static func expectedPreparationPlan(
        startedAt unixSeconds: UInt64
    ) -> OpalFusion.Runtime.CovertPreparationPlan {
        let startedAt = instant(unixSeconds)
        return .init(
            endpoint: covertEndpointContext,
            startedAt: startedAt,
            deadline: startedAt.advanced(by: baseline.covertTiming.connectWindow)
        )
    }

    static func expectedRequest(
        for message: OpalFusion.ProtocolModel.CovertMessage,
        startedAt unixSeconds: UInt64,
        roundIdentifier: OpalFusion.Round.Identifier? = nil
    ) throws -> OpalFusion.Runtime.CovertRequest {
        let startedAt = instant(unixSeconds)
        return .init(
            endpoint: covertEndpointContext,
            roundIdentifier: roundIdentifier,
            payload: try encodeCovertMessagePayload(message),
            startedAt: startedAt,
            deadline: startedAt.advanced(by: baseline.covertTiming.submitTimeout)
        )
    }

    static func driveThroughStartRound(
        session: inout OpalFusion.Runtime.PrimaryRuntimeSession
    ) throws {
        try driveThroughWarmup(session: &session)
        _ = session.apply(
            input: .receivedPrimaryBytes(try encodeServerFrame(.startRound(startRound))),
            now: instant(1_030)
        )
    }

    static func driveThroughWarmup(
        session: inout OpalFusion.Runtime.PrimaryRuntimeSession
    ) throws {
        _ = session.apply(input: .connected, now: instant(995))
        _ = session.apply(
            input: .receivedPrimaryBytes(try encodeServerFrame(.serverHello(serverHello))),
            now: instant(996)
        )
        _ = session.apply(
            input: .receivedPrimaryBytes(try encodeServerFrame(.fusionBegin(fusionBegin))),
            now: instant(1_000)
        )
    }

    static func markCovertPrepared(
        session: inout OpalFusion.Runtime.PrimaryRuntimeSession
    ) {
        _ = session.apply(
            input: .covertPrepared,
            now: instant(1_001)
        )
    }

    static func driveToAwaitingCovertSubmission(
        session: inout OpalFusion.Runtime.PrimaryRuntimeSession
    ) throws {
        try driveThroughStartRound(session: &session)
        _ = session.apply(
            input: .participantReservationLoaded(participantReservation),
            now: instant(1_031)
        )
        _ = session.apply(
            input: .receivedPrimaryBytes(
                try encodeServerFrame(.blindSignatureResponses(blindSignatureResponses))
            ),
            now: instant(1_032)
        )
        _ = session.apply(
            input: .receivedPrimaryBytes(try encodeServerFrame(.allCommitments(allCommitments))),
            now: instant(1_034)
        )
    }

    static func driveToAwaitingSharedComponents(
        session: inout OpalFusion.Runtime.PrimaryRuntimeSession
    ) throws {
        try driveToAwaitingCovertSubmission(session: &session)
        markCovertPrepared(session: &session)
        _ = session.apply(
            input: .clockAdvanced,
            now: instant(1_035)
        )
        _ = session.apply(
            input: .receivedCovertResponseBytes(
                try encodeCovertResponsePayload(acknowledgement)
            ),
            now: instant(1_036)
        )
    }
}
