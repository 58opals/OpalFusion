// CashFusionOfficialProtobufFixtureValidator.swift

@testable import OpalFusion
import Testing

struct CashFusionOfficialProtobufFixtureValidator {
    func expectPrimaryPayload<Value: Equatable>(
        _ value: Value,
        bytes: [UInt8],
        encode: (Value) throws -> [UInt8],
        decode: ([UInt8]) throws -> Value
    ) throws {
        #expect(try encode(value) == bytes)
        #expect(try decode(bytes) == value)
    }

    func expectCovertPayload<Value: Equatable>(
        _ value: Value,
        bytes: [UInt8],
        encode: (Value) throws -> [UInt8],
        decode: ([UInt8]) throws -> Value
    ) throws {
        #expect(try encode(value) == bytes)
        #expect(try decode(bytes) == value)
    }
}
