// CashFusionCovertMessageCodecValidator+EnvelopeFixtures.swift

@testable import OpalFusion
import Testing

extension CashFusionCovertMessageCodecValidator {
    static func makeConflictingCovertEnvelope() throws -> [UInt8] {
        CashFusionOfficialProtobufFixtures.conflictingCovertEnvelopeBytes
    }

    static func makeConflictingCovertResponseEnvelope() throws -> [UInt8] {
        CashFusionOfficialProtobufFixtures.conflictingCovertResponseEnvelopeBytes
    }

    static func makeCovertFailureEnvelopeWithInvalidMessage() throws -> [UInt8] {
        CashFusionOfficialProtobufFixtures.covertFailureEnvelopeWithInvalidMessageBytes
    }

    static func expectCovertError<Success>(
        _ expectedError: OpalFusion.Wire.CovertMessageCodecError,
        from operation: () throws -> Success
    ) {
        #expect(throws: expectedError) {
            _ = try operation()
        }
    }

    static func expectCodingError<Success>(
        _ expectedError: OpalFusion.Wire.CashFusionProtobufCodingError,
        from operation: () throws -> Success
    ) {
        #expect(throws: expectedError) {
            _ = try operation()
        }
    }
}
