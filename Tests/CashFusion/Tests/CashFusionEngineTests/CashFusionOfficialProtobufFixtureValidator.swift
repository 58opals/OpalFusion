// CashFusionOfficialProtobufFixtureValidator.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
import Testing
import CryptoKit
import Foundation

struct CashFusionOfficialProtobufFixtureValidator {
    @Test("Preserve independently requalified Electron Cash fixture provenance")
    func validateQualifiedSourceAndFixtureIdentity() throws {
        var canonical = Data()
        let fixtures = CashFusionOfficialProvenance.fixtures.sorted { $0.name < $1.name }
        #expect(fixtures.count == 37)
        #expect(Set(fixtures.map(\.name)).count == fixtures.count)
        for fixture in fixtures {
            canonical.append(contentsOf: fixture.name.utf8)
            canonical.append(0)
            let count = UInt32(fixture.bytes.count)
            canonical.append(contentsOf: [
                UInt8(count >> 24), UInt8(truncatingIfNeeded: count >> 16),
                UInt8(truncatingIfNeeded: count >> 8), UInt8(truncatingIfNeeded: count)
            ])
            canonical.append(contentsOf: fixture.bytes)
        }
        let digest = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        #expect(digest == CashFusionOfficialProvenance.fixtureSHA256)

        let documentURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../docs/reference-fixture-provenance.md")
        let document = try String(contentsOf: documentURL, encoding: .utf8)
        let sourceRoot = "https://raw.githubusercontent.com/Electron-Cash/Electron-Cash/"
            + CashFusionOfficialProvenance.sourceCommit + "/"
        for path in [
            "electroncash_plugins/fusion/protobuf/fusion.proto",
            "electroncash_plugins/fusion/connection.py",
            "electroncash_plugins/fusion/protocol.py", "LICENCE"
        ] {
            #expect(document.contains(sourceRoot + path))
        }
        for identity in [
            CashFusionOfficialProvenance.sourceCommit,
            CashFusionOfficialProvenance.schemaSHA256,
            CashFusionOfficialProvenance.framingSHA256,
            CashFusionOfficialProvenance.protocolSHA256,
            CashFusionOfficialProvenance.licenseSHA256,
            CashFusionOfficialProvenance.fixtureSHA256
        ] {
            #expect(document.contains(identity))
        }
    }

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
