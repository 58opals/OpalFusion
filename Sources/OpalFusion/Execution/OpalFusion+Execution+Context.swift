// OpalFusion+Execution+Context.swift

import OpalCrypto

extension OpalFusion.Execution {
    enum ConnectionSubstate: String, Sendable, Equatable {
        case disconnected
        case awaitingServerHello
        case awaitingFusionBegin
        case inRound
        case failed
    }

    struct SessionContext: Sendable, Equatable {
        let configuration: OpalFusion.Client.Configuration
        let baseline: OpalFusion.Transport.BaselineConfiguration
        let genesisHash: [UInt8]?
        let joinPools: OpalFusion.ProtocolModel.JoinPools
        var latestServerHello: OpalFusion.ProtocolModel.ServerHello?
        var latestTierStatus: OpalFusion.ProtocolModel.TierStatusUpdate?
        var isConnected: Bool
        var restartCount: Int
        var connectionSubstate: OpalFusion.Execution.ConnectionSubstate
        var lastError: OpalFusion.Client.Error?

        init(
            configuration: OpalFusion.Client.Configuration,
            baseline: OpalFusion.Transport.BaselineConfiguration,
            genesisHash: [UInt8]?,
            joinPools: OpalFusion.ProtocolModel.JoinPools
        ) {
            self.configuration = configuration
            self.baseline = baseline
            self.genesisHash = genesisHash
            self.joinPools = joinPools
            self.latestServerHello = nil
            self.latestTierStatus = nil
            self.isConnected = false
            self.restartCount = 0
            self.connectionSubstate = .disconnected
            self.lastError = nil
        }
    }

    enum RoundSubstate: String, Sendable, Equatable {
        case warmup
        case collectingInputs
        case awaitingBlindSignatures
        case awaitingAllCommitments
        case awaitingCovertComponentWindow
        case submittingCovertComponents
        case awaitingSharedComponents
        case awaitingHostFinalization
        case awaitingSignatureWindow
        case submittingSignatures
        case awaitingResult
        case awaitingTheirProofs
        case submittingBlames
        case awaitingRestart
        case terminal
    }

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

    struct RoundContext: Sendable {
        let fusionBegin: OpalFusion.ProtocolModel.FusionBegin
        let serverHello: OpalFusion.ProtocolModel.ServerHello
        var startRound: OpalFusion.ProtocolModel.StartRound?
        var identifier: OpalFusion.Round.Identifier?
        var participantReservation: OpalFusion.Host.ParticipantReservation?
        var playerCommit: OpalFusion.ProtocolModel.PlayerCommit?
        var blindSignatureResponses: OpalFusion.ProtocolModel.BlindSignatureResponses?
        var allCommitments: OpalFusion.ProtocolModel.AllCommitments?
        var sharedComponents: OpalFusion.ProtocolModel.ShareCovertComponents?
        var finalizedTransaction: OpalFusion.Host.FinalizedTransaction?
        var fusionResult: OpalFusion.ProtocolModel.FusionResult?
        var myProofsList: OpalFusion.ProtocolModel.MyProofsList?
        var theirProofsList: OpalFusion.ProtocolModel.TheirProofsList?
        var blames: OpalFusion.ProtocolModel.Blames?
        var substate: OpalFusion.Execution.RoundSubstate
        var deadlines: OpalFusion.Execution.Deadlines
        var completionStatus: OpalFusion.Round.CompletionStatus?
        var executionMaterial: OpalFusion.Execution.ExecutionMaterial

        init(
            fusionBegin: OpalFusion.ProtocolModel.FusionBegin,
            serverHello: OpalFusion.ProtocolModel.ServerHello,
            deadlines: OpalFusion.Execution.Deadlines
        ) {
            self.fusionBegin = fusionBegin
            self.serverHello = serverHello
            self.startRound = nil
            self.identifier = nil
            self.participantReservation = nil
            self.playerCommit = nil
            self.blindSignatureResponses = nil
            self.allCommitments = nil
            self.sharedComponents = nil
            self.finalizedTransaction = nil
            self.fusionResult = nil
            self.myProofsList = nil
            self.theirProofsList = nil
            self.blames = nil
            self.substate = .warmup
            self.deadlines = deadlines
            self.completionStatus = nil
            self.executionMaterial = .init()
        }
    }

    struct ExecutionMaterial: Sendable {
        var playerCommitMaterial: OpalFusion.Execution.PlayerCommitMaterial?
        var finalizedBlindSignatures: [[UInt8]]
        var sharedRoundMaterial: OpalFusion.Execution.SharedRoundMaterial?

        init() {
            self.playerCommitMaterial = nil
            self.finalizedBlindSignatures = []
            self.sharedRoundMaterial = nil
        }
    }

    struct PlayerCommitMaterial: Sendable {
        let componentsByCommitmentOrder: [OpalFusion.Execution.LocalComponentMaterial]
        let blindSignatureRequests: [OpalCrypto.BlindSignature.Request]
        let pedersenTotalNonce: [UInt8]
        let excessFeeSatoshis: UInt64
        let randomNumber: [UInt8]
    }

    struct LocalComponentMaterial: Sendable {
        let originalSlot: Int
        let payload: OpalFusion.Commitment.ComponentPayload
        let serializedComponent: [UInt8]
        let serializedInitialCommitment: [UInt8]
        let initialCommitment: OpalFusion.Commitment.InitialCommitment
        let proofMaterial: OpalFusion.Execution.UnassignedProofMaterial
        let communicationPrivateKey: [UInt8]
        let contributionSatoshis: Int64
    }

    struct UnassignedProofMaterial: Sendable {
        let salt: [UInt8]
        let pedersenNonce: [UInt8]
    }

    struct SharedRoundMaterial: Sendable {
        let allCommitmentBytes: [[UInt8]]
        let allComponentBytes: [[UInt8]]
        let sessionHash: [UInt8]
        let decodedComponents: [OpalFusion.Execution.DecodedComponent]
        let myCommitmentIndices: [Int]
        let myComponentIndices: [Int]
        let transactionTemplate: OpalFusion.Execution.BCHTransaction
        let transactionInputComponentIndices: [Int]
        let localInputReferences: [OpalFusion.Execution.LocalInputReference]
    }

    struct DecodedComponent: Sendable {
        let serializedComponent: [UInt8]
        let saltCommitment: [UInt8]
        let payload: OpalFusion.Commitment.ComponentPayload
    }

    struct LocalInputReference: Sendable {
        let transactionInputIndex: Int
        let componentIndex: Int
        let reservationInputIndex: Int
        let originalSlot: Int
        let participantInput: OpalFusion.Host.ParticipantInput
    }
}
