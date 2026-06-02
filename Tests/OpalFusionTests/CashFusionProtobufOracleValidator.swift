// CashFusionProtobufOracleValidator.swift

@testable import OpalFusion
import Testing

struct CashFusionProtobufOracleValidator {
    @Test("CashFusion protobuf primitives match pinned ClientHello bytes")
    func validateClientHelloPinnedBytes() throws {
        let versionBytes: [UInt8] = [0x61, 0x6C, 0x70, 0x68, 0x61, 0x31, 0x33]
        let genesisHash = [UInt8](repeating: 0xAA, count: 32)
        let pinnedBytes = CashFusionPinnedProtobufFixtures.primitiveClientHelloBytes
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBytesField(
            versionBytes,
            fieldNumber: 1
        )
        try writer.writeBytesField(
            genesisHash,
            fieldNumber: 2
        )
        #expect(writer.serializedBytes == pinnedBytes)

        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: pinnedBytes)
        let versionHeader = try #require(try reader.readNextFieldHeader())
        #expect(versionHeader.number == 1)
        #expect(try reader.readBytesValue(for: versionHeader) == versionBytes)

        let genesisHeader = try #require(try reader.readNextFieldHeader())
        #expect(genesisHeader.number == 2)
        #expect(try reader.readBytesValue(for: genesisHeader) == genesisHash)
        #expect(reader.isAtEnd)
    }

    @Test("CashFusion protobuf primitives match pinned Error bytes")
    func validateErrorPinnedBytes() throws {
        let pinnedBytes = CashFusionPinnedProtobufFixtures.primitiveErrorBytes
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeStringField(
            "bad request",
            fieldNumber: 1
        )
        #expect(writer.serializedBytes == pinnedBytes)

        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: pinnedBytes)
        let messageHeader = try #require(try reader.readNextFieldHeader())
        #expect(messageHeader.number == 1)
        #expect(try reader.readStringValue(for: messageHeader) == "bad request")
        #expect(reader.isAtEnd)
    }
}
