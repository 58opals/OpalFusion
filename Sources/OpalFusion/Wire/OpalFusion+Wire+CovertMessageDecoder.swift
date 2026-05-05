// OpalFusion+Wire+CovertMessageDecoder.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import SwiftProtobuf

extension OpalFusion.Wire {
    struct CovertMessageDecoder: Sendable {
        func decodeMessage(_ bytes: [UInt8]) throws -> OpalFusion.ProtocolModel.CovertMessage {
            do {
                let envelope = try FusionCovertMessage(serializedBytes: bytes)
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
                let envelope = try FusionCovertResponse(serializedBytes: bytes)
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

private extension OpalFusion.Wire.CovertMessageDecoder {
    func decodeCovertEnvelope(
        _ envelope: FusionCovertMessage
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
        _ envelope: FusionCovertResponse
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

    func decode(_ message: FusionCovertComponent) -> OpalFusion.ProtocolModel.CovertComponent {
        .init(
            roundPublicKey: message.hasRoundPubkey ? [UInt8](message.roundPubkey) : nil,
            signature: [UInt8](message.signature),
            serializedComponent: [UInt8](message.component)
        )
    }

    func decode(
        _ message: FusionCovertTransactionSignature
    ) -> OpalFusion.ProtocolModel.CovertTransactionSignature {
        .init(
            roundPublicKey: message.hasRoundPubkey ? [UInt8](message.roundPubkey) : nil,
            inputIndex: message.whichInput,
            transactionSignature: [UInt8](message.txsignature)
        )
    }

    func decode(_ message: FusionError) -> OpalFusion.ProtocolModel.ServerFailure {
        .init(
            message: message.hasMessage ? message.message : nil
        )
    }
}
