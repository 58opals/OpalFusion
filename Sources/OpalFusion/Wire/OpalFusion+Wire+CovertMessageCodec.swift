// OpalFusion+Wire+CovertMessageCodec.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import SwiftProtobuf

extension OpalFusion.Wire {
    enum CovertMessageCodecError: Swift.Error, Equatable {
        case missingCovertMessageCase
        case missingCovertResponseCase
        case protobufCodingFailed(String)
    }

    struct CovertMessageEncoder: Sendable {
        func encode(_ message: OpalFusion.ProtocolModel.CovertMessage) throws -> [UInt8] {
            do {
                return try encodeCovertEnvelope(message).serializedBytes()
            } catch {
                throw OpalFusion.Wire.CovertMessageCodecError.protobufCodingFailed(
                    String(describing: error)
                )
            }
        }

        func encode(_ response: OpalFusion.ProtocolModel.CovertResponse) throws -> [UInt8] {
            do {
                return try encodeCovertResponseEnvelope(response).serializedBytes()
            } catch {
                throw OpalFusion.Wire.CovertMessageCodecError.protobufCodingFailed(
                    String(describing: error)
                )
            }
        }
    }

    struct CovertMessageDecoder: Sendable {
        func decodeMessage(_ bytes: [UInt8]) throws -> OpalFusion.ProtocolModel.CovertMessage {
            do {
                let envelope = try Fusion_CovertMessage(serializedBytes: bytes)
                return try decodeCovertEnvelope(envelope)
            } catch let error as OpalFusion.Wire.CovertMessageCodecError {
                throw error
            } catch {
                throw OpalFusion.Wire.CovertMessageCodecError.protobufCodingFailed(
                    String(describing: error)
                )
            }
        }

        func decodeResponse(_ bytes: [UInt8]) throws -> OpalFusion.ProtocolModel.CovertResponse {
            do {
                let envelope = try Fusion_CovertResponse(serializedBytes: bytes)
                return try decodeCovertResponseEnvelope(envelope)
            } catch let error as OpalFusion.Wire.CovertMessageCodecError {
                throw error
            } catch {
                throw OpalFusion.Wire.CovertMessageCodecError.protobufCodingFailed(
                    String(describing: error)
                )
            }
        }
    }
}

private extension OpalFusion.Wire.CovertMessageEncoder {
    func encodeCovertEnvelope(
        _ message: OpalFusion.ProtocolModel.CovertMessage
    ) -> Fusion_CovertMessage {
        var envelope = Fusion_CovertMessage()

        switch message {
        case let .component(component):
            envelope.component = encode(component)
        case let .transactionSignature(signature):
            envelope.signature = encode(signature)
        case .ping:
            envelope.ping = .init()
        }

        return envelope
    }

    func encodeCovertResponseEnvelope(
        _ response: OpalFusion.ProtocolModel.CovertResponse
    ) -> Fusion_CovertResponse {
        var envelope = Fusion_CovertResponse()

        switch response {
        case .acknowledgement:
            envelope.ok = .init()
        case let .serverFailure(failure):
            envelope.error = encode(failure)
        }

        return envelope
    }

    func encode(_ message: OpalFusion.ProtocolModel.CovertComponent) -> Fusion_CovertComponent {
        var proto = Fusion_CovertComponent()
        if let roundPublicKey = message.roundPublicKey {
            proto.roundPubkey = Data(roundPublicKey)
        }
        proto.signature = Data(message.signature)
        proto.component = Data(message.serializedComponent)
        return proto
    }

    func encode(
        _ message: OpalFusion.ProtocolModel.CovertTransactionSignature
    ) -> Fusion_CovertTransactionSignature {
        var proto = Fusion_CovertTransactionSignature()
        if let roundPublicKey = message.roundPublicKey {
            proto.roundPubkey = Data(roundPublicKey)
        }
        proto.whichInput = message.inputIndex
        proto.txsignature = Data(message.transactionSignature)
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

private extension OpalFusion.Wire.CovertMessageDecoder {
    func decodeCovertEnvelope(
        _ envelope: Fusion_CovertMessage
    ) throws -> OpalFusion.ProtocolModel.CovertMessage {
        guard let message = envelope.msg else {
            throw OpalFusion.Wire.CovertMessageCodecError.missingCovertMessageCase
        }

        switch message {
        case let .component(component):
            return .component(decode(component))
        case let .signature(signature):
            return .transactionSignature(decode(signature))
        case .ping:
            return .ping(.init())
        }
    }

    func decodeCovertResponseEnvelope(
        _ envelope: Fusion_CovertResponse
    ) throws -> OpalFusion.ProtocolModel.CovertResponse {
        guard let message = envelope.msg else {
            throw OpalFusion.Wire.CovertMessageCodecError.missingCovertResponseCase
        }

        switch message {
        case .ok:
            return .acknowledgement(.init())
        case let .error(error):
            return .serverFailure(decode(error))
        }
    }

    func decode(_ message: Fusion_CovertComponent) -> OpalFusion.ProtocolModel.CovertComponent {
        .init(
            roundPublicKey: message.hasRoundPubkey ? [UInt8](message.roundPubkey) : nil,
            signature: [UInt8](message.signature),
            serializedComponent: [UInt8](message.component)
        )
    }

    func decode(
        _ message: Fusion_CovertTransactionSignature
    ) -> OpalFusion.ProtocolModel.CovertTransactionSignature {
        .init(
            roundPublicKey: message.hasRoundPubkey ? [UInt8](message.roundPubkey) : nil,
            inputIndex: message.whichInput,
            transactionSignature: [UInt8](message.txsignature)
        )
    }

    func decode(_ message: Fusion_Error) -> OpalFusion.ProtocolModel.ServerFailure {
        .init(
            message: message.hasMessage ? message.message : nil
        )
    }
}
