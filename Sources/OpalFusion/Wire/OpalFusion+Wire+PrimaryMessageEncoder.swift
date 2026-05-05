// OpalFusion+Wire+PrimaryMessageEncoder.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import SwiftProtobuf

extension OpalFusion.Wire {
    struct PrimaryMessageEncoder: Sendable {
        func encode(_ message: OpalFusion.ProtocolModel.ClientMessage) throws -> [UInt8] {
            do {
                return try encodeClientEnvelope(message).serializedBytes()
            } catch {
                throw OpalFusion.Wire.PrimaryMessageCodecError.protobufDecodingFailed(
                    String(describing: error)
                )
            }
        }

        func encode(_ message: OpalFusion.ProtocolModel.ServerMessage) throws -> [UInt8] {
            do {
                return try encodeServerEnvelope(message).serializedBytes()
            } catch {
                throw OpalFusion.Wire.PrimaryMessageCodecError.protobufDecodingFailed(
                    String(describing: error)
                )
            }
        }
    }
}

private extension OpalFusion.Wire.PrimaryMessageEncoder {
    func encodeClientEnvelope(
        _ message: OpalFusion.ProtocolModel.ClientMessage
    ) throws -> FusionClientMessage {
        var envelope = FusionClientMessage()

        switch message {
        case let .clientHello(clientHello):
            envelope.clienthello = encode(clientHello)
        case let .joinPools(joinPools):
            envelope.joinpools = encode(joinPools)
        case let .playerCommit(playerCommit):
            envelope.playercommit = try encode(playerCommit)
        case let .myProofsList(myProofsList):
            envelope.myproofslist = encode(myProofsList)
        case let .blames(blames):
            envelope.blames = encode(blames)
        }

        return envelope
    }

    func encodeServerEnvelope(
        _ message: OpalFusion.ProtocolModel.ServerMessage
    ) throws -> FusionServerMessage {
        var envelope = FusionServerMessage()

        switch message {
        case let .serverHello(serverHello):
            envelope.serverhello = encode(serverHello)
        case let .tierStatusUpdate(update):
            envelope.tierstatusupdate = encode(update)
        case let .fusionBegin(fusionBegin):
            envelope.fusionbegin = encode(fusionBegin)
        case let .startRound(startRound):
            envelope.startround = encode(startRound)
        case let .blindSignatureResponses(responses):
            envelope.blindsigresponses = encode(responses)
        case let .allCommitments(allCommitments):
            envelope.allcommitments = try encode(allCommitments)
        case let .shareCovertComponents(components):
            envelope.sharecovertcomponents = encode(components)
        case let .fusionResult(result):
            envelope.fusionresult = encode(result)
        case let .theirProofsList(proofs):
            envelope.theirproofslist = encode(proofs)
        case .restartRound:
            envelope.restartround = .init()
        case let .serverFailure(failure):
            envelope.error = encode(failure)
        }

        return envelope
    }

    func encode(_ message: OpalFusion.ProtocolModel.ClientHello) -> FusionClientHello {
        var proto = FusionClientHello()
        proto.version = Data(message.versionBytes)
        if let genesisHash = message.genesisHash {
            proto.genesisHash = Data(genesisHash)
        }
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.JoinPools) -> FusionJoinPools {
        var proto = FusionJoinPools()
        proto.tiers = message.tiers
        proto.tags = message.tags.map(encode)
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.PoolTag) -> FusionJoinPools.PoolTag {
        var proto = FusionJoinPools.PoolTag()
        proto.id = Data(message.identifier)
        proto.limit = message.limit
        if let noIp = message.noIp {
            proto.noIp = noIp
        }
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.PlayerCommit) throws -> FusionPlayerCommit {
        var proto = FusionPlayerCommit()
        proto.initialCommitments = try message.initialCommitments.map {
            try encode($0).serializedData()
        }
        proto.excessFee = message.excessFeeSatoshis
        proto.pedersenTotalNonce = Data(message.pedersenTotalNonce)
        proto.randomNumberCommitment = Data(message.randomNumberCommitment)
        proto.blindSigRequests = message.blindSignatureRequests.map {
            Data($0.scalar)
        }
        return proto
    }

    func encode(
        _ message: OpalFusion.Commitment.InitialCommitment
    ) -> FusionInitialCommitment {
        var proto = FusionInitialCommitment()
        proto.saltedComponentHash = Data(message.saltedComponentHash)
        proto.amountCommitment = Data(message.amountCommitment)
        proto.communicationKey = Data(message.communicationPublicKey)
        return proto
    }

    func encode(
        _ message: OpalFusion.ProtocolModel.MyProofsList
    ) -> FusionMyProofsList {
        var proto = FusionMyProofsList()
        proto.encryptedProofs = message.encryptedProofs.map { Data($0) }
        proto.randomNumber = Data(message.randomNumber)
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.Blames) -> FusionBlames {
        var proto = FusionBlames()
        proto.blames = message.blames.map(encode)
        return proto
    }

    func encode(_ message: OpalFusion.Blame.BlameProof) -> FusionBlames.BlameProof {
        var proto = FusionBlames.BlameProof()
        proto.whichProof = message.proofIndex

        switch message.decrypter {
        case let .sessionKey(sessionKey):
            proto.sessionKey = Data(sessionKey)
        case let .privateKey(privateKey):
            proto.privkey = Data(privateKey)
        }

        if let requiresLookup = message.requiresBlockchainLookup {
            proto.needLookupBlockchain = requiresLookup
        }
        if let reason = message.reason {
            proto.blameReason = reason
        }
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.ServerHello) -> FusionServerHello {
        var proto = FusionServerHello()
        proto.tiers = message.tiers
        proto.numComponents = message.numberOfComponents
        proto.componentFeerate = message.componentFeeRateSatoshisPerKb
        proto.minExcessFee = message.minimumExcessFeeSatoshis
        proto.maxExcessFee = message.maximumExcessFeeSatoshis
        if let donationAddress = message.donationAddress {
            proto.donationAddress = donationAddress
        }
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.TierStatusUpdate) -> FusionTierStatusUpdate {
        var proto = FusionTierStatusUpdate()
        proto.statuses = Dictionary(
            uniqueKeysWithValues: message.statusesByTier.map { key, value in
                (key, encode(value))
            }
        )
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.TierStatus) -> FusionTierStatusUpdate.TierStatus {
        var proto = FusionTierStatusUpdate.TierStatus()
        if let playerCount = message.playerCount {
            proto.players = playerCount
        }
        if let minimumPlayerCount = message.minimumPlayerCount {
            proto.minPlayers = minimumPlayerCount
        }
        if let maximumPlayerCount = message.maximumPlayerCount {
            proto.maxPlayers = maximumPlayerCount
        }
        if let timeRemainingSeconds = message.timeRemainingSeconds {
            proto.timeRemaining = timeRemainingSeconds
        }
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.FusionBegin) -> FusionBeginMessage {
        var proto = FusionBeginMessage()
        proto.tier = message.tier
        proto.covertDomain = Data(message.covertDomain.utf8)
        proto.covertPort = message.covertPort
        if let covertSsl = message.covertSsl {
            proto.covertSsl = covertSsl
        }
        proto.serverTime = message.serverTimeUnixSeconds
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.StartRound) -> FusionStartRound {
        var proto = FusionStartRound()
        proto.roundPubkey = Data(message.roundPublicKey)
        proto.blindNoncePoints = message.blindNoncePoints.map { Data($0) }
        proto.serverTime = message.serverTimeUnixSeconds
        return proto
    }

    func encode(
        _ message: OpalFusion.ProtocolModel.BlindSignatureResponses
    ) -> FusionBlindSignatureResponses {
        var proto = FusionBlindSignatureResponses()
        proto.scalars = message.responses.map { Data($0.scalar) }
        return proto
    }

    func encode(
        _ message: OpalFusion.ProtocolModel.AllCommitments
    ) throws -> FusionAllCommitments {
        var proto = FusionAllCommitments()
        proto.initialCommitments = try message.initialCommitments.map {
            try encode($0).serializedData()
        }
        return proto
    }

    func encode(
        _ message: OpalFusion.ProtocolModel.ShareCovertComponents
    ) -> FusionShareCovertComponents {
        var proto = FusionShareCovertComponents()
        proto.components = message.serializedComponents.map { Data($0) }
        if let skipSignatures = message.skipSignatures {
            proto.skipSignatures = skipSignatures
        }
        if let sessionHash = message.sessionHash {
            proto.sessionHash = Data(sessionHash)
        }
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.FusionResult) -> FusionResultMessage {
        var proto = FusionResultMessage()
        proto.ok = message.isSuccess
        proto.txsignatures = message.transactionSignatures.map { Data($0) }
        proto.badComponents = message.badComponentIndices
        return proto
    }

    func encode(
        _ message: OpalFusion.ProtocolModel.TheirProofsList
    ) -> FusionTheirProofsList {
        var proto = FusionTheirProofsList()
        proto.proofs = message.proofs.map(encode)
        return proto
    }

    func encode(_ message: OpalFusion.Blame.RelayedProof) -> FusionTheirProofsList.RelayedProof {
        var proto = FusionTheirProofsList.RelayedProof()
        proto.encryptedProof = Data(message.encryptedProof)
        proto.srcCommitmentIdx = message.sourceCommitmentIndex
        proto.dstKeyIdx = message.destinationKeyIndex
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.ServerFailure) -> FusionError {
        var proto = FusionError()
        if let text = message.message {
            proto.message = text
        }
        return proto
    }
}
