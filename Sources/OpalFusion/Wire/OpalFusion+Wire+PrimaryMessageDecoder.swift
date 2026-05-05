// OpalFusion+Wire+PrimaryMessageDecoder.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import SwiftProtobuf

extension OpalFusion.Wire {
    struct PrimaryMessageDecoder: Sendable {
        func decodeClient(_ bytes: [UInt8]) throws -> OpalFusion.ProtocolModel.ClientMessage {
            do {
                let envelope = try FusionClientMessage(serializedBytes: bytes)
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
                let envelope = try FusionServerMessage(serializedBytes: bytes)
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

private extension OpalFusion.Wire.PrimaryMessageDecoder {
    func decodeClientEnvelope(
        _ envelope: FusionClientMessage
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
        _ envelope: FusionServerMessage
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

    func decode(_ message: FusionClientHello) -> OpalFusion.ProtocolModel.ClientHello {
        .init(
            versionBytes: [UInt8](message.version),
            genesisHash: message.hasGenesisHash ? [UInt8](message.genesisHash) : nil
        )
    }

    func decode(_ message: FusionJoinPools) -> OpalFusion.ProtocolModel.JoinPools {
        .init(
            tiers: message.tiers,
            tags: message.tags.map(decode)
        )
    }

    func decode(_ message: FusionJoinPools.PoolTag) -> OpalFusion.ProtocolModel.PoolTag {
        .init(
            identifier: [UInt8](message.id),
            limit: message.limit,
            noIp: message.hasNoIp ? message.noIp : nil
        )
    }

    func decode(_ message: FusionPlayerCommit) throws -> OpalFusion.ProtocolModel.PlayerCommit {
        .init(
            initialCommitments: try message.initialCommitments.map {
                let proto = try FusionInitialCommitment(serializedBytes: $0)
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
        _ message: FusionInitialCommitment
    ) -> OpalFusion.Commitment.InitialCommitment {
        .init(
            saltedComponentHash: [UInt8](message.saltedComponentHash),
            amountCommitment: [UInt8](message.amountCommitment),
            communicationPublicKey: [UInt8](message.communicationKey)
        )
    }

    func decode(_ message: FusionMyProofsList) -> OpalFusion.ProtocolModel.MyProofsList {
        .init(
            encryptedProofs: message.encryptedProofs.map { [UInt8]($0) },
            randomNumber: [UInt8](message.randomNumber)
        )
    }

    func decode(_ message: FusionBlames) throws -> OpalFusion.ProtocolModel.Blames {
        .init(
            blames: try message.blames.map { try decode($0) }
        )
    }

    func decode(_ message: FusionBlames.BlameProof) throws -> OpalFusion.Blame.BlameProof {
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

    func decode(_ message: FusionServerHello) -> OpalFusion.ProtocolModel.ServerHello {
        .init(
            tiers: message.tiers,
            numberOfComponents: message.numComponents,
            componentFeeRateSatoshisPerKb: message.componentFeerate,
            minimumExcessFeeSatoshis: message.minExcessFee,
            maximumExcessFeeSatoshis: message.maxExcessFee,
            donationAddress: message.hasDonationAddress ? message.donationAddress : nil
        )
    }

    func decode(_ message: FusionTierStatusUpdate) -> OpalFusion.ProtocolModel.TierStatusUpdate {
        .init(
            statusesByTier: Dictionary(
                uniqueKeysWithValues: message.statuses.map { key, value in
                    (key, decode(value))
                }
            )
        )
    }

    func decode(_ message: FusionTierStatusUpdate.TierStatus) -> OpalFusion.ProtocolModel.TierStatus {
        .init(
            playerCount: message.hasPlayers ? message.players : nil,
            minimumPlayerCount: message.hasMinPlayers ? message.minPlayers : nil,
            maximumPlayerCount: message.hasMaxPlayers ? message.maxPlayers : nil,
            timeRemainingSeconds: message.hasTimeRemaining ? message.timeRemaining : nil
        )
    }

    func decode(_ message: FusionBeginMessage) throws -> OpalFusion.ProtocolModel.FusionBegin {
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

    func decode(_ message: FusionStartRound) -> OpalFusion.ProtocolModel.StartRound {
        .init(
            roundPublicKey: [UInt8](message.roundPubkey),
            blindNoncePoints: message.blindNoncePoints.map { [UInt8]($0) },
            serverTimeUnixSeconds: message.serverTime
        )
    }

    func decode(_ message: FusionBlindSignatureResponses) -> OpalFusion.ProtocolModel.BlindSignatureResponses {
        .init(
            responses: message.scalars.map { .init(scalar: [UInt8]($0)) }
        )
    }

    func decode(_ message: FusionAllCommitments) throws -> OpalFusion.ProtocolModel.AllCommitments {
        .init(
            initialCommitments: try message.initialCommitments.map {
                let proto = try FusionInitialCommitment(serializedBytes: $0)
                return decode(proto)
            }
        )
    }

    func decode(
        _ message: FusionShareCovertComponents
    ) -> OpalFusion.ProtocolModel.ShareCovertComponents {
        .init(
            serializedComponents: message.components.map { [UInt8]($0) },
            skipSignatures: message.hasSkipSignatures ? message.skipSignatures : nil,
            sessionHash: message.hasSessionHash ? [UInt8](message.sessionHash) : nil
        )
    }

    func decode(_ message: FusionResultMessage) -> OpalFusion.ProtocolModel.FusionResult {
        .init(
            isSuccess: message.ok,
            transactionSignatures: message.txsignatures.map { [UInt8]($0) },
            badComponentIndices: message.badComponents
        )
    }

    func decode(
        _ message: FusionTheirProofsList
    ) -> OpalFusion.ProtocolModel.TheirProofsList {
        .init(
            proofs: message.proofs.map(decode)
        )
    }

    func decode(_ message: FusionTheirProofsList.RelayedProof) -> OpalFusion.Blame.RelayedProof {
        .init(
            encryptedProof: [UInt8](message.encryptedProof),
            sourceCommitmentIndex: message.srcCommitmentIdx,
            destinationKeyIndex: message.dstKeyIdx
        )
    }

    func decode(_ message: FusionError) -> OpalFusion.ProtocolModel.ServerFailure {
        .init(
            message: message.hasMessage ? message.message : nil
        )
    }
}
