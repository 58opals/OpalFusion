// CashFusionRequiredFieldCodecValidator.swift

@testable import OpalFusion
import Testing

struct CashFusionRequiredFieldCodecValidator {
    @Test("CashFusion primary codec rejects missing official required fields")
    func validatePrimaryMissingRequiredFields() {
        Self.expectMissingRequiredField("ClientHello", 1) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeClientHello([])
        }
        Self.expectMissingRequiredField("ServerHello", 2) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeServerHello([0x20, 0x00, 0x28, 0x00, 0x30, 0x00])
        }
        Self.expectMissingRequiredField("ServerHello", 4) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeServerHello([0x10, 0x00, 0x28, 0x00, 0x30, 0x00])
        }
        Self.expectMissingRequiredField("ServerHello", 5) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeServerHello([0x10, 0x00, 0x20, 0x00, 0x30, 0x00])
        }
        Self.expectMissingRequiredField("ServerHello", 6) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeServerHello([0x10, 0x00, 0x20, 0x00, 0x28, 0x00])
        }
        Self.expectMissingRequiredField("PoolTag", 1) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodePoolTag([0x10, 0x00])
        }
        Self.expectMissingRequiredField("PoolTag", 2) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodePoolTag([0x0A, 0x00])
        }
        Self.expectMissingRequiredField("FusionBegin", 1) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeFusionBegin([0x12, 0x00, 0x18, 0x00] + Self.fixed64ServerTime)
        }
        Self.expectMissingRequiredField("FusionBegin", 2) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeFusionBegin([0x08, 0x00, 0x18, 0x00] + Self.fixed64ServerTime)
        }
        Self.expectMissingRequiredField("FusionBegin", 3) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeFusionBegin([0x08, 0x00, 0x12, 0x00] + Self.fixed64ServerTime)
        }
        Self.expectMissingRequiredField("FusionBegin", 5) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeFusionBegin([0x08, 0x00, 0x12, 0x00, 0x18, 0x00])
        }
        Self.expectMissingRequiredField("StartRound", 1) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeStartRound(Self.fixed64ServerTime)
        }
        Self.expectMissingRequiredField("StartRound", 5) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeStartRound([0x0A, 0x00])
        }
    }

    @Test("CashFusion round and blame codecs reject missing official required fields")
    func validateRoundAndBlameMissingRequiredFields() {
        Self.expectMissingRequiredField("PlayerCommit", 2) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodePlayerCommit([0x1A, 0x00, 0x22, 0x00])
        }
        Self.expectMissingRequiredField("PlayerCommit", 3) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodePlayerCommit([0x10, 0x00, 0x22, 0x00])
        }
        Self.expectMissingRequiredField("PlayerCommit", 4) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodePlayerCommit([0x10, 0x00, 0x1A, 0x00])
        }
        Self.expectMissingRequiredField("FusionResult", 1) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeFusionResult([])
        }
        Self.expectMissingRequiredField("MyProofsList", 2) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeMyProofsList([])
        }
        Self.expectMissingRequiredField("RelayedProof", 1) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeRelayedProof([0x10, 0x00, 0x18, 0x00])
        }
        Self.expectMissingRequiredField("RelayedProof", 2) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeRelayedProof([0x0A, 0x00, 0x18, 0x00])
        }
        Self.expectMissingRequiredField("RelayedProof", 3) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeRelayedProof([0x0A, 0x00, 0x10, 0x00])
        }
        Self.expectMissingRequiredField("BlameProof", 1) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeBlameProof([0x12, 0x00])
        }
    }

    @Test("CashFusion covert codec rejects missing official required fields")
    func validateCovertMissingRequiredFields() {
        Self.expectMissingRequiredField("CovertComponent", 2) {
            try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeCovertComponent([0x1A, 0x00])
        }
        Self.expectMissingRequiredField("CovertComponent", 3) {
            try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeCovertComponent([0x12, 0x00])
        }
        Self.expectMissingRequiredField("CovertTransactionSignature", 2) {
            try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeCovertTransactionSignature([0x1A, 0x00])
        }
        Self.expectMissingRequiredField("CovertTransactionSignature", 3) {
            try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeCovertTransactionSignature([0x10, 0x00])
        }
    }

    @Test("CashFusion strict codec preserves focused malformed error precedence")
    func validateFocusedMalformedPrecedence() {
        Self.expectPrimaryError(.missingBlameDecrypter) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeBlameProof([0x08, 0x00])
        }
        Self.expectCodingError(.conflictingOneOfField(messageName: "BlameProof", fieldNumber: 3)) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeBlameProof([0x08, 0x00, 0x12, 0x00, 0x1A, 0x00])
        }
        Self.expectPrimaryError(.invalidUTF8Field("BlameProof.blameReason")) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeBlameProof([0x08, 0x00, 0x12, 0x00, 0x2A, 0x01, 0xFF])
        }
        Self.expectCodingError(.invalidUTF8String) {
            try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeServerFailure([0x0A, 0x01, 0xFF])
        }
        Self.expectCodingError(.uint32ValueOutOfRange(4_294_967_296)) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeRelayedProof([0x0A, 0x00, 0x10] + Self.uint32OverflowValue + [0x18, 0x00])
        }
        Self.expectCodingError(.uint32ValueOutOfRange(4_294_967_296)) {
            try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeCovertTransactionSignature([0x10] + Self.uint32OverflowValue + [0x1A, 0x00])
        }
        Self.expectCodingError(.truncatedInput) {
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodePlayerCommit([0x0A, 0x01, 0x0A, 0x10, 0x00, 0x1A, 0x00, 0x22, 0x00])
        }
    }

    private static let fixed64ServerTime: [UInt8] = [
        0x29, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00
    ]

    private static let uint32OverflowValue: [UInt8] = [
        0x80, 0x80, 0x80, 0x80, 0x10
    ]

    private static func expectMissingRequiredField<Success>(
        _ messageName: String,
        _ fieldNumber: Int,
        from operation: () throws -> Success
    ) {
        expectCodingError(
            .missingRequiredField(
                messageName: messageName,
                fieldNumber: fieldNumber
            ),
            from: operation
        )
    }

    private static func expectPrimaryError<Success>(
        _ expectedError: OpalFusion.Wire.PrimaryMessageCodecError,
        from operation: () throws -> Success
    ) {
        #expect(throws: expectedError) {
            _ = try operation()
        }
    }

    private static func expectCodingError<Success>(
        _ expectedError: OpalFusion.Wire.CashFusionProtobufCodingError,
        from operation: () throws -> Success
    ) {
        #expect(throws: expectedError) {
            _ = try operation()
        }
    }
}
