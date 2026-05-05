// OpalFusion+Wire+CovertMessageEncoder.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import SwiftProtobuf

extension OpalFusion.Wire {
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
}

private extension OpalFusion.Wire.CovertMessageEncoder {
    func encodeCovertEnvelope(
        _ message: OpalFusion.ProtocolModel.CovertMessage
    ) -> FusionCovertMessage {
        var envelope = FusionCovertMessage()

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
    ) -> FusionCovertResponse {
        var envelope = FusionCovertResponse()

        switch response {
        case .acknowledgement:
            envelope.ok = .init()
        case let .serverFailure(failure):
            envelope.error = encode(failure)
        }

        return envelope
    }

    func encode(_ message: OpalFusion.ProtocolModel.CovertComponent) -> FusionCovertComponent {
        var proto = FusionCovertComponent()
        if let roundPublicKey = message.roundPublicKey {
            proto.roundPubkey = Data(roundPublicKey)
        }
        proto.signature = Data(message.signature)
        proto.component = Data(message.serializedComponent)
        return proto
    }

    func encode(
        _ message: OpalFusion.ProtocolModel.CovertTransactionSignature
    ) -> FusionCovertTransactionSignature {
        var proto = FusionCovertTransactionSignature()
        if let roundPublicKey = message.roundPublicKey {
            proto.roundPubkey = Data(roundPublicKey)
        }
        proto.whichInput = message.inputIndex
        proto.txsignature = Data(message.transactionSignature)
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
