// MosaicOpalV0WireContractValidator+Components.swift

@testable import OpalFusion
import Testing

extension MosaicOpalV0WireContractValidator {
    @Test("Input output and blank components match their pinned kind layouts")
    func validateComponentGoldenVectors() throws {
        let input = try Self.makeInputComponent()
        let inputBytes = try Codec.encodeComponent(input)
        #expect(
            inputBytes
                == Self.indexedDigest(1)
                    + [0x00]
                    + Self.indexedDigest(2)
                    + Self.uint32Bytes(3)
                    + Self.uint64Bytes(4)
        )
        #expect(try Codec.decodeComponent(from: inputBytes) == input)

        let output = try Self.makeOutputComponent()
        let outputBytes = try Codec.encodeComponent(output)
        #expect(
            outputBytes
                == Self.indexedDigest(5)
                    + [0x01]
                    + Self.p2pkhLockingScript()
                    + Self.uint64Bytes(7)
        )
        #expect(try Codec.decodeComponent(from: outputBytes) == output)

        let blank = try Self.makeBlankComponent(index: 9)
        let blankBytes = try Codec.encodeComponent(blank)
        #expect(blankBytes == Self.indexedDigest(9) + [0x02])
        #expect(try Codec.decodeComponent(from: blankBytes) == blank)
    }

    @Test("Components reject malformed hashes amounts scripts and kinds")
    func rejectMalformedComponents() throws {
        #expect(throws: WireContractError.invalidSaltCommitmentLength(actual: 31)) {
            _ = try OpalV0.Component(
                saltCommitment: [UInt8](repeating: 0, count: 31),
                payload: .blank
            )
        }
        #expect(
            throws: WireContractError.invalidInputTransactionHashLength(actual: 31)
        ) {
            _ = try OpalV0.InputComponent(
                previousTransactionHash: [UInt8](repeating: 0, count: 31),
                outputIndex: 0,
                amountSatoshis: 1
            )
        }
        #expect(throws: WireContractError.invalidComponentAmount(actual: 0)) {
            _ = try OpalV0.InputComponent(
                previousTransactionHash: Self.indexedDigest(0),
                outputIndex: 0,
                amountSatoshis: 0
            )
        }
        #expect(
            throws: WireContractError.invalidComponentAmount(
                actual: OpalV0.maximumMoneySatoshis + 1
            )
        ) {
            _ = try OpalV0.OutputComponent(
                lockingScript: Self.p2pkhLockingScript(),
                amountSatoshis: OpalV0.maximumMoneySatoshis + 1
            )
        }
        #expect(throws: WireContractError.invalidP2PKHLockingScript) {
            _ = try OpalV0.OutputComponent(
                lockingScript: [UInt8](repeating: 0, count: 25),
                amountSatoshis: 1
            )
        }
        #expect(throws: WireContractError.unknownComponentKind(0x03)) {
            _ = try Codec.decodeComponent(
                from: Self.indexedDigest(0) + [0x03]
            )
        }
    }

    @Test("Component decoders reject truncated and trailing bytes")
    func rejectMalformedComponentBytes() throws {
        let inputBytes = try Codec.encodeComponent(Self.makeInputComponent())
        #expect(throws: OpalFusion.Mosaic.CanonicalCodingError.self) {
            _ = try Codec.decodeComponent(from: Array(inputBytes.dropLast()))
        }

        let blankBytes = try Codec.encodeComponent(Self.makeBlankComponent(index: 0))
        #expect(
            throws: OpalFusion.Mosaic.CanonicalCodingError.trailingBytes(1)
        ) {
            _ = try Codec.decodeComponent(from: blankBytes + [0x00])
        }
    }

    @Test("Anonymous component payloads pin token and component bytes to one round")
    func validateAnonymousComponentGoldenVector() throws {
        let roundIdentifier = [UInt8](repeating: 0x11, count: 32)
        let component = try Self.makeBlankComponent(index: 9)
        let payload = try OpalV0.AnonymousComponentPayload(
            roundIdentifier: roundIdentifier,
            authorizationToken: Self.makeAuthorizationToken(
                roundIdentifier: roundIdentifier
            ),
            component: component
        )
        let encoded = try Codec.encodeAnonymousComponent(payload)
        let expected = roundIdentifier
            + Self.rawAuthorizationTokenBytes(roundIdentifier: roundIdentifier)
            + Self.indexedDigest(9)
            + [0x02]

        #expect(encoded == expected)
        #expect(encoded.count == 449)
        #expect(
            Self.sha256Hexadecimal(encoded)
                == "efe254819dc63cdaa744e118d7eb3de20230d02d63b85ccf3ffcd0ce5a025a55"
        )
        #expect(try Codec.decodeAnonymousComponent(from: encoded) == payload)
    }

    @Test("Anonymous component payloads reject invalid or substituted rounds")
    func rejectAnonymousComponentRoundViolations() throws {
        let token = try Self.makeAuthorizationToken()
        let component = try Self.makeBlankComponent(index: 0)
        #expect(throws: WireContractError.invalidRoundIdentifierLength(actual: 31)) {
            _ = try OpalV0.AnonymousComponentPayload(
                roundIdentifier: [UInt8](repeating: 0x11, count: 31),
                authorizationToken: token,
                component: component
            )
        }
        #expect(throws: WireContractError.authorizationTokenRoundMismatch) {
            _ = try OpalV0.AnonymousComponentPayload(
                roundIdentifier: [UInt8](repeating: 0x12, count: 32),
                authorizationToken: token,
                component: component
            )
        }

        let encoded = try Codec.encodeAnonymousComponent(
            .init(
                roundIdentifier: [UInt8](repeating: 0x11, count: 32),
                authorizationToken: token,
                component: component
            )
        )
        var substituted = encoded
        substituted[0] = 0x12
        #expect(throws: WireContractError.authorizationTokenRoundMismatch) {
            _ = try Codec.decodeAnonymousComponent(from: substituted)
        }
    }

    @Test("Pre-sign acknowledgements match the pinned round-root document")
    func validatePreSignAcknowledgementGoldenVector() throws {
        let payload = try OpalV0.PreSignAcknowledgementPayload(
            roundIdentifier: [UInt8](repeating: 0x11, count: 32),
            transcriptRoot: [UInt8](repeating: 0x22, count: 32)
        )
        let encoded = try Codec.encodePreSignAcknowledgement(payload)
        #expect(
            encoded
                == [UInt8](repeating: 0x11, count: 32)
                    + [UInt8](repeating: 0x22, count: 32)
        )
        #expect(try Codec.decodePreSignAcknowledgement(from: encoded) == payload)

        #expect(throws: WireContractError.invalidRoundIdentifierLength(actual: 31)) {
            _ = try OpalV0.PreSignAcknowledgementPayload(
                roundIdentifier: [UInt8](repeating: 0, count: 31),
                transcriptRoot: [UInt8](repeating: 0, count: 32)
            )
        }
        #expect(throws: WireContractError.invalidTranscriptRootLength(actual: 33)) {
            _ = try OpalV0.PreSignAcknowledgementPayload(
                roundIdentifier: [UInt8](repeating: 0, count: 32),
                transcriptRoot: [UInt8](repeating: 0, count: 33)
            )
        }
    }
}
