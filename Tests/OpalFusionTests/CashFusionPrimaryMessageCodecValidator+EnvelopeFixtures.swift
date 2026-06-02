// CashFusionPrimaryMessageCodecValidator+EnvelopeFixtures.swift

@testable import OpalFusion
import Testing

extension CashFusionPrimaryMessageCodecValidator {
    static func makeClientBlamesEnvelopeWithoutDecrypter() throws -> [UInt8] {
        CashFusionOfficialProtobufFixtures.clientBlamesEnvelopeWithoutDecrypterBytes
    }

    static func makeConflictingClientEnvelope() throws -> [UInt8] {
        CashFusionOfficialProtobufFixtures.conflictingClientEnvelopeBytes
    }

    static func makeServerFusionBeginEnvelopeWithInvalidDomain() throws -> [UInt8] {
        CashFusionOfficialProtobufFixtures.serverFusionBeginEnvelopeWithInvalidDomainBytes
    }

    static func makeServerFailureEnvelopeWithInvalidMessage() throws -> [UInt8] {
        CashFusionOfficialProtobufFixtures.serverFailureEnvelopeWithInvalidMessageBytes
    }

    static func expectPrimaryError<Success>(
        _ expectedError: OpalFusion.Wire.PrimaryMessageCodecError,
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
