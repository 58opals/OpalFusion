// PrimaryFrameValidator.swift

@testable import OpalFusion
import Testing

struct PrimaryFrameValidator {
    @Test("Primary framing round-trips a valid payload")
    func validateRoundTrip() throws {
        let configuration = OpalFusion.Transport.BaselineConfiguration.electronCash443.framing
        let encoder = OpalFusion.Wire.PrimaryFrameEncoder(configuration: configuration)
        var decoder = OpalFusion.Wire.PrimaryFrameDecoder(configuration: configuration)
        let payload: [UInt8] = [0x01, 0x02, 0x03]

        let frame = try encoder.encode(payload: payload)

        #expect(Array(frame.prefix(configuration.magicBytes.count)) == configuration.magicBytes)
        #expect(
            Array(frame[configuration.magicBytes.count..<(configuration.magicBytes.count + 4)])
                == [0x00, 0x00, 0x00, 0x03]
        )
        #expect(try decoder.append(frame) == [payload])
        #expect(decoder.bufferedBytes.isEmpty)
    }

    @Test("Primary frame decoder handles fragmented inbound bytes")
    func validateFragmentedInput() throws {
        let configuration = OpalFusion.Transport.BaselineConfiguration.electronCash443.framing
        let encoder = OpalFusion.Wire.PrimaryFrameEncoder(configuration: configuration)
        var decoder = OpalFusion.Wire.PrimaryFrameDecoder(configuration: configuration)
        let frame = try encoder.encode(payload: [0x10, 0x11, 0x12, 0x13])

        #expect(try decoder.append(Array(frame[..<5])).isEmpty)
        #expect(decoder.bufferedBytes == Array(frame[..<5]))
        #expect(try decoder.append(Array(frame[5..<11])).isEmpty)
        #expect(try decoder.append(Array(frame[11...])) == [[0x10, 0x11, 0x12, 0x13]])
        #expect(decoder.bufferedBytes.isEmpty)
    }

    @Test("Primary frame decoder rejects invalid magic")
    func validateInvalidMagic() {
        let configuration = OpalFusion.Transport.BaselineConfiguration.electronCash443.framing
        var decoder = OpalFusion.Wire.PrimaryFrameDecoder(configuration: configuration)
        let invalidMagic = Array(repeating: UInt8(0xFF), count: configuration.magicBytes.count)
        let frame = invalidMagic + [0x00, 0x00, 0x00, 0x01, 0x42]

        do {
            _ = try decoder.append(frame)
            Issue.record("Expected invalid magic rejection")
        } catch let error as OpalFusion.Wire.PrimaryFrameError {
            #expect(error == .invalidMagic(invalidMagic))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Primary frame decoder rejects oversized payload declarations")
    func validateOversizedPayload() {
        let configuration = OpalFusion.Transport.BaselineConfiguration.electronCash443.framing
        var decoder = OpalFusion.Wire.PrimaryFrameDecoder(configuration: configuration)
        let oversizedLength = configuration.maximumMessageLengthBytes + 1
        let frame = configuration.magicBytes + Self.bigEndianBytes(for: oversizedLength)

        do {
            _ = try decoder.append(frame)
            Issue.record("Expected oversized payload rejection")
        } catch let error as OpalFusion.Wire.PrimaryFrameError {
            #expect(error == .payloadTooLarge(oversizedLength))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Primary frame decoder rejects zero-length frames")
    func validateZeroLengthFrame() {
        let configuration = OpalFusion.Transport.BaselineConfiguration.electronCash443.framing
        var decoder = OpalFusion.Wire.PrimaryFrameDecoder(configuration: configuration)
        let frame = configuration.magicBytes + [0x00, 0x00, 0x00, 0x00]

        do {
            _ = try decoder.append(frame)
            Issue.record("Expected invalid length rejection")
        } catch let error as OpalFusion.Wire.PrimaryFrameError {
            #expect(error == .invalidLength(0))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private extension PrimaryFrameValidator {
    static func bigEndianBytes(for value: Int) -> [UInt8] {
        let length = UInt32(value)
        return [
            UInt8((length >> 24) & 0xFF),
            UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF)
        ]
    }
}
