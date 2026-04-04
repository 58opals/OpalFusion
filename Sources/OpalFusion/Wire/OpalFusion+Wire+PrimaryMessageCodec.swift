// OpalFusion+Wire+PrimaryMessageCodec.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import SwiftProtobuf

extension OpalFusion.Wire {
    enum PrimaryMessageCodecError: Swift.Error, Equatable {
        case missingClientMessageCase
        case missingServerMessageCase
        case missingBlameDecrypter
        case invalidUTF8Field(String)
        case protobufDecodingFailed(String)
    }

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

    struct PrimaryMessageDecoder: Sendable {
        func decodeClient(_ bytes: [UInt8]) throws -> OpalFusion.ProtocolModel.ClientMessage {
            do {
                let envelope = try Fusion_ClientMessage(serializedBytes: bytes)
                return try decodeClientEnvelope(envelope)
            } catch let error as OpalFusion.Wire.PrimaryMessageCodecError {
                throw error
            } catch {
                throw OpalFusion.Wire.PrimaryMessageCodecError.protobufDecodingFailed(
                    String(describing: error)
                )
            }
        }

        func decodeServer(_ bytes: [UInt8]) throws -> OpalFusion.ProtocolModel.ServerMessage {
            do {
                let envelope = try Fusion_ServerMessage(serializedBytes: bytes)
                return try decodeServerEnvelope(envelope)
            } catch let error as OpalFusion.Wire.PrimaryMessageCodecError {
                throw error
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
    ) throws -> Fusion_ClientMessage {
        var envelope = Fusion_ClientMessage()

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
    ) throws -> Fusion_ServerMessage {
        var envelope = Fusion_ServerMessage()

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

    func encode(_ message: OpalFusion.ProtocolModel.ClientHello) -> Fusion_ClientHello {
        var proto = Fusion_ClientHello()
        proto.version = Data(message.versionBytes)
        if let genesisHash = message.genesisHash {
            proto.genesisHash = Data(genesisHash)
        }
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.JoinPools) -> Fusion_JoinPools {
        var proto = Fusion_JoinPools()
        proto.tiers = message.tiers
        proto.tags = message.tags.map(encode)
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.PoolTag) -> Fusion_JoinPools.PoolTag {
        var proto = Fusion_JoinPools.PoolTag()
        proto.id = Data(message.identifier)
        proto.limit = message.limit
        if let noIp = message.noIp {
            proto.noIp = noIp
        }
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.PlayerCommit) throws -> Fusion_PlayerCommit {
        var proto = Fusion_PlayerCommit()
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
    ) -> Fusion_InitialCommitment {
        var proto = Fusion_InitialCommitment()
        proto.saltedComponentHash = Data(message.saltedComponentHash)
        proto.amountCommitment = Data(message.amountCommitment)
        proto.communicationKey = Data(message.communicationPublicKey)
        return proto
    }

    func encode(
        _ message: OpalFusion.ProtocolModel.MyProofsList
    ) -> Fusion_MyProofsList {
        var proto = Fusion_MyProofsList()
        proto.encryptedProofs = message.encryptedProofs.map { Data($0) }
        proto.randomNumber = Data(message.randomNumber)
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.Blames) -> Fusion_Blames {
        var proto = Fusion_Blames()
        proto.blames = message.blames.map(encode)
        return proto
    }

    func encode(_ message: OpalFusion.Blame.BlameProof) -> Fusion_Blames.BlameProof {
        var proto = Fusion_Blames.BlameProof()
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

    func encode(_ message: OpalFusion.ProtocolModel.ServerHello) -> Fusion_ServerHello {
        var proto = Fusion_ServerHello()
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

    func encode(_ message: OpalFusion.ProtocolModel.TierStatusUpdate) -> Fusion_TierStatusUpdate {
        var proto = Fusion_TierStatusUpdate()
        proto.statuses = Dictionary(
            uniqueKeysWithValues: message.statusesByTier.map { key, value in
                (key, encode(value))
            }
        )
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.TierStatus) -> Fusion_TierStatusUpdate.TierStatus {
        var proto = Fusion_TierStatusUpdate.TierStatus()
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

    func encode(_ message: OpalFusion.ProtocolModel.FusionBegin) -> Fusion_FusionBegin {
        var proto = Fusion_FusionBegin()
        proto.tier = message.tier
        proto.covertDomain = Data(message.covertDomain.utf8)
        proto.covertPort = message.covertPort
        if let covertSsl = message.covertSsl {
            proto.covertSsl = covertSsl
        }
        proto.serverTime = message.serverTimeUnixSeconds
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.StartRound) -> Fusion_StartRound {
        var proto = Fusion_StartRound()
        proto.roundPubkey = Data(message.roundPublicKey)
        proto.blindNoncePoints = message.blindNoncePoints.map { Data($0) }
        proto.serverTime = message.serverTimeUnixSeconds
        return proto
    }

    func encode(
        _ message: OpalFusion.ProtocolModel.BlindSignatureResponses
    ) -> Fusion_BlindSigResponses {
        var proto = Fusion_BlindSigResponses()
        proto.scalars = message.responses.map { Data($0.scalar) }
        return proto
    }

    func encode(
        _ message: OpalFusion.ProtocolModel.AllCommitments
    ) throws -> Fusion_AllCommitments {
        var proto = Fusion_AllCommitments()
        proto.initialCommitments = try message.initialCommitments.map {
            try encode($0).serializedData()
        }
        return proto
    }

    func encode(
        _ message: OpalFusion.ProtocolModel.ShareCovertComponents
    ) -> Fusion_ShareCovertComponents {
        var proto = Fusion_ShareCovertComponents()
        proto.components = message.serializedComponents.map { Data($0) }
        if let skipSignatures = message.skipSignatures {
            proto.skipSignatures = skipSignatures
        }
        if let sessionHash = message.sessionHash {
            proto.sessionHash = Data(sessionHash)
        }
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.FusionResult) -> Fusion_FusionResult {
        var proto = Fusion_FusionResult()
        proto.ok = message.isSuccess
        proto.txsignatures = message.transactionSignatures.map { Data($0) }
        proto.badComponents = message.badComponentIndices
        return proto
    }

    func encode(
        _ message: OpalFusion.ProtocolModel.TheirProofsList
    ) -> Fusion_TheirProofsList {
        var proto = Fusion_TheirProofsList()
        proto.proofs = message.proofs.map(encode)
        return proto
    }

    func encode(_ message: OpalFusion.Blame.RelayedProof) -> Fusion_TheirProofsList.RelayedProof {
        var proto = Fusion_TheirProofsList.RelayedProof()
        proto.encryptedProof = Data(message.encryptedProof)
        proto.srcCommitmentIdx = message.sourceCommitmentIndex
        proto.dstKeyIdx = message.destinationKeyIndex
        return proto
    }

    func encode(_ message: OpalFusion.ProtocolModel.ServerFailure) -> Fusion_Error {
        var proto = Fusion_Error()
        if let text = message.message {
            proto.message = text
        }
        return proto
    }
}

private extension OpalFusion.Wire.PrimaryMessageDecoder {
    func decodeClientEnvelope(
        _ envelope: Fusion_ClientMessage
    ) throws -> OpalFusion.ProtocolModel.ClientMessage {
        guard let message = envelope.msg else {
            throw OpalFusion.Wire.PrimaryMessageCodecError.missingClientMessageCase
        }

        switch message {
        case let .clienthello(clientHello):
            return .clientHello(decode(clientHello))
        case let .joinpools(joinPools):
            return .joinPools(decode(joinPools))
        case let .playercommit(playerCommit):
            return .playerCommit(try decode(playerCommit))
        case let .myproofslist(myProofsList):
            return .myProofsList(decode(myProofsList))
        case let .blames(blames):
            return .blames(try decode(blames))
        }
    }

    func decodeServerEnvelope(
        _ envelope: Fusion_ServerMessage
    ) throws -> OpalFusion.ProtocolModel.ServerMessage {
        guard let message = envelope.msg else {
            throw OpalFusion.Wire.PrimaryMessageCodecError.missingServerMessageCase
        }

        switch message {
        case let .serverhello(serverHello):
            return .serverHello(decode(serverHello))
        case let .tierstatusupdate(update):
            return .tierStatusUpdate(decode(update))
        case let .fusionbegin(fusionBegin):
            return .fusionBegin(try decode(fusionBegin))
        case let .startround(startRound):
            return .startRound(decode(startRound))
        case let .blindsigresponses(responses):
            return .blindSignatureResponses(decode(responses))
        case let .allcommitments(allCommitments):
            return .allCommitments(try decode(allCommitments))
        case let .sharecovertcomponents(components):
            return .shareCovertComponents(decode(components))
        case let .fusionresult(result):
            return .fusionResult(decode(result))
        case let .theirproofslist(proofs):
            return .theirProofsList(decode(proofs))
        case .restartround:
            return .restartRound(.init())
        case let .error(error):
            return .serverFailure(decode(error))
        }
    }

    func decode(_ message: Fusion_ClientHello) -> OpalFusion.ProtocolModel.ClientHello {
        .init(
            versionBytes: [UInt8](message.version),
            genesisHash: message.hasGenesisHash ? [UInt8](message.genesisHash) : nil
        )
    }

    func decode(_ message: Fusion_JoinPools) -> OpalFusion.ProtocolModel.JoinPools {
        .init(
            tiers: message.tiers,
            tags: message.tags.map(decode)
        )
    }

    func decode(_ message: Fusion_JoinPools.PoolTag) -> OpalFusion.ProtocolModel.PoolTag {
        .init(
            identifier: [UInt8](message.id),
            limit: message.limit,
            noIp: message.hasNoIp ? message.noIp : nil
        )
    }

    func decode(_ message: Fusion_PlayerCommit) throws -> OpalFusion.ProtocolModel.PlayerCommit {
        .init(
            initialCommitments: try message.initialCommitments.map {
                let proto = try Fusion_InitialCommitment(serializedBytes: $0)
                return decode(proto)
            },
            excessFeeSatoshis: message.excessFee,
            pedersenTotalNonce: [UInt8](message.pedersenTotalNonce),
            randomNumberCommitment: [UInt8](message.randomNumberCommitment),
            blindSignatureRequests: message.blindSigRequests.map {
                .init(scalar: [UInt8]($0))
            }
        )
    }

    func decode(
        _ message: Fusion_InitialCommitment
    ) -> OpalFusion.Commitment.InitialCommitment {
        .init(
            saltedComponentHash: [UInt8](message.saltedComponentHash),
            amountCommitment: [UInt8](message.amountCommitment),
            communicationPublicKey: [UInt8](message.communicationKey)
        )
    }

    func decode(_ message: Fusion_MyProofsList) -> OpalFusion.ProtocolModel.MyProofsList {
        .init(
            encryptedProofs: message.encryptedProofs.map { [UInt8]($0) },
            randomNumber: [UInt8](message.randomNumber)
        )
    }

    func decode(_ message: Fusion_Blames) throws -> OpalFusion.ProtocolModel.Blames {
        .init(
            blames: try message.blames.map { try decode($0) }
        )
    }

    func decode(_ message: Fusion_Blames.BlameProof) throws -> OpalFusion.Blame.BlameProof {
        let decrypter: OpalFusion.Blame.Decrypter
        switch message.decrypter {
        case let .sessionKey(sessionKey):
            decrypter = .sessionKey([UInt8](sessionKey))
        case let .privkey(privateKey):
            decrypter = .privateKey([UInt8](privateKey))
        case nil:
            throw OpalFusion.Wire.PrimaryMessageCodecError.missingBlameDecrypter
        }

        return .init(
            proofIndex: message.whichProof,
            decrypter: decrypter,
            requiresBlockchainLookup: message.hasNeedLookupBlockchain ? message.needLookupBlockchain : nil,
            reason: message.hasBlameReason ? message.blameReason : nil
        )
    }

    func decode(_ message: Fusion_ServerHello) -> OpalFusion.ProtocolModel.ServerHello {
        .init(
            tiers: message.tiers,
            numberOfComponents: message.numComponents,
            componentFeeRateSatoshisPerKb: message.componentFeerate,
            minimumExcessFeeSatoshis: message.minExcessFee,
            maximumExcessFeeSatoshis: message.maxExcessFee,
            donationAddress: message.hasDonationAddress ? message.donationAddress : nil
        )
    }

    func decode(_ message: Fusion_TierStatusUpdate) -> OpalFusion.ProtocolModel.TierStatusUpdate {
        .init(
            statusesByTier: Dictionary(
                uniqueKeysWithValues: message.statuses.map { key, value in
                    (key, decode(value))
                }
            )
        )
    }

    func decode(_ message: Fusion_TierStatusUpdate.TierStatus) -> OpalFusion.ProtocolModel.TierStatus {
        .init(
            playerCount: message.hasPlayers ? message.players : nil,
            minimumPlayerCount: message.hasMinPlayers ? message.minPlayers : nil,
            maximumPlayerCount: message.hasMaxPlayers ? message.maxPlayers : nil,
            timeRemainingSeconds: message.hasTimeRemaining ? message.timeRemaining : nil
        )
    }

    func decode(_ message: Fusion_FusionBegin) throws -> OpalFusion.ProtocolModel.FusionBegin {
        guard let covertDomain = String(data: message.covertDomain, encoding: .utf8) else {
            throw OpalFusion.Wire.PrimaryMessageCodecError.invalidUTF8Field(
                "FusionBegin.covertDomain"
            )
        }

        return .init(
            tier: message.tier,
            covertDomain: covertDomain,
            covertPort: message.covertPort,
            covertSsl: message.hasCovertSsl ? message.covertSsl : nil,
            serverTimeUnixSeconds: message.serverTime
        )
    }

    func decode(_ message: Fusion_StartRound) -> OpalFusion.ProtocolModel.StartRound {
        .init(
            roundPublicKey: [UInt8](message.roundPubkey),
            blindNoncePoints: message.blindNoncePoints.map { [UInt8]($0) },
            serverTimeUnixSeconds: message.serverTime
        )
    }

    func decode(_ message: Fusion_BlindSigResponses) -> OpalFusion.ProtocolModel.BlindSignatureResponses {
        .init(
            responses: message.scalars.map { .init(scalar: [UInt8]($0)) }
        )
    }

    func decode(_ message: Fusion_AllCommitments) throws -> OpalFusion.ProtocolModel.AllCommitments {
        .init(
            initialCommitments: try message.initialCommitments.map {
                let proto = try Fusion_InitialCommitment(serializedBytes: $0)
                return decode(proto)
            }
        )
    }

    func decode(
        _ message: Fusion_ShareCovertComponents
    ) -> OpalFusion.ProtocolModel.ShareCovertComponents {
        .init(
            serializedComponents: message.components.map { [UInt8]($0) },
            skipSignatures: message.hasSkipSignatures ? message.skipSignatures : nil,
            sessionHash: message.hasSessionHash ? [UInt8](message.sessionHash) : nil
        )
    }

    func decode(_ message: Fusion_FusionResult) -> OpalFusion.ProtocolModel.FusionResult {
        .init(
            isSuccess: message.ok,
            transactionSignatures: message.txsignatures.map { [UInt8]($0) },
            badComponentIndices: message.badComponents
        )
    }

    func decode(
        _ message: Fusion_TheirProofsList
    ) -> OpalFusion.ProtocolModel.TheirProofsList {
        .init(
            proofs: message.proofs.map(decode)
        )
    }

    func decode(_ message: Fusion_TheirProofsList.RelayedProof) -> OpalFusion.Blame.RelayedProof {
        .init(
            encryptedProof: [UInt8](message.encryptedProof),
            sourceCommitmentIndex: message.srcCommitmentIdx,
            destinationKeyIndex: message.dstKeyIdx
        )
    }

    func decode(_ message: Fusion_Error) -> OpalFusion.ProtocolModel.ServerFailure {
        .init(
            message: message.hasMessage ? message.message : nil
        )
    }
}
