import Foundation
import Testing
@testable import FusionValidation

private let proofRevisions = ["117949b08f354f5a58b78075dbf14b2ec4e4f88f", "79ba5f91449b2c0d5cd6ec73c38fafd58cae0b46"]
private let historicalPaths = [
    "Sources/OpalFusion/Mosaic/OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapConsensusEnvelope.swift",
    "Sources/OpalFusion/Mosaic/OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapEnvelope.swift",
    "Sources/OpalFusion/Mosaic/OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapPublicationRestoration.swift",
    "Tests/OpalFusionTests/MosaicPrivateAlphaTransportBootstrapValidator.swift"
]

private final class ParserFixture {
    let runner: RunnerFixture
    var root: URL { runner.root }
    var calls: URL { root.appendingPathComponent("proof-calls.jsonl") }
    var registry: URL { root.appendingPathComponent("docs/mosaic-g4-parser-implementation-files-2026-08-23.txt") }
    init() throws {
        runner = try RunnerFixture()
        let script = root.appendingPathComponent("scripts/check-mosaic-g4-parser-root-registry.sh")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: repositoryRoot().appendingPathComponent("scripts/check-mosaic-g4-parser-root-registry.sh"), to: script)
        for name in ["mosaic-g4-parser-implementation-files-2026-08-23.txt", "mosaic-g4-parser-root-map-2026-08-23.txt", "mosaic-g4-parser-composite-root-map-2026-08-23.txt"] {
            let destination = root.appendingPathComponent("docs/" + name)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: repositoryRoot().appendingPathComponent("docs/" + name), to: destination)
        }
        for name in try String(contentsOf: registry, encoding: .utf8).split(separator: "\n") {
            try write("CanonicalDecoder.decode\n", to: root.appendingPathComponent(String(name)))
        }
        let current = historicalPaths.prefix(3).map { root.appendingPathComponent($0.replacingOccurrences(of: "Sources/OpalFusion/", with: "Sources/MosaicEngine/")) }
        for path in current where !FileManager.default.fileExists(atPath: path.path) { try write("", to: path) }
        let roots = try String(contentsOf: root.appendingPathComponent("docs/mosaic-g4-parser-composite-root-map-2026-08-23.txt"), encoding: .utf8).split(separator: "\n")
        let declarations = roots.map { "public static func " + $0.components(separatedBy: " :: ")[0] + "() {}\n" }.joined()
        try write(try String(contentsOf: current[0], encoding: .utf8) + declarations, to: current[0])
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("bin/git"), withDestinationURL: runner.fixtureExecutable)
    }
    func invoke(_ overrides: [String: String] = [:]) throws -> (code: Int32, calls: [[String]], output: String) {
        try write("", to: calls)
        var environment = runner.environment.merging(overrides, uniquingKeysWith: { _, new in new })
        environment["PROOF_CALLS"] = calls.path
        let owner = ValidationProcess(environment: environment)
        var output = ""
        var code: Int32 = 0
        do {
            output = try owner.run(["/bin/sh", root.appendingPathComponent("scripts/check-mosaic-g4-parser-root-registry.sh").path], deadline: monotonicTime() + 10, capture: true)
        } catch let error as CommandFailure { code = error.status }
        let recorded = try String(contentsOf: calls, encoding: .utf8).split(separator: "\n").map { line in
            try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String])
        }
        return (code, recorded, output)
    }
}

struct ParserHistoricalProofContract {
    @Test func missingHistoricalEvidenceCannotAdvertiseParity() throws {
        let fixture = try ParserFixture()
        for revision in proofRevisions {
            for path in historicalPaths {
                let result = try fixture.invoke(["MISSING_PROOF_OBJECT": revision + ":" + path])
                #expect(result.code != 0)
                #expect(!result.output.contains("passing G2 parity retained"))
                #expect(!result.calls.contains(where: { $0.contains("diff") }))
            }
        }
    }

    @Test func changedHistoricalSourcesCannotPassVacuousPathspec() throws {
        let fixture = try ParserFixture()
        let result = try fixture.invoke(["CHANGED_PROOF_FILE": "1"])
        #expect(result.code != 0)
        #expect(!result.output.contains("passing G2 parity retained"))
        let differences = result.calls.filter { $0.contains("diff") }
        #expect(differences.count == 1)
        let diff = try #require(differences.first)
        #expect(Array(diff.dropFirst(try #require(diff.firstIndex(of: "--")) + 1)) == historicalPaths)
    }

    @Test func eachRequiredFileExistsInBothProofRevisionsBeforeComparison() throws {
        let fixture = try ParserFixture()
        let result = try fixture.invoke()
        #expect(result.code == 0)
        #expect(result.calls.filter { $0.contains("cat-file") }.compactMap(\.last) == proofRevisions.flatMap { revision in historicalPaths.map { revision + ":" + $0 } })
        #expect(result.calls.count == 9)
        #expect(result.output.contains("passing G2 parity retained"))
    }

    @Test func jsonDecoderScanPreservesRegisteredFileMembership() throws {
        let fixture = try ParserFixture()
        let name = try #require(String(contentsOf: fixture.registry, encoding: .utf8).split(separator: "\n").first)
        let path = fixture.root.appendingPathComponent(String(name))
        try write(try String(contentsOf: path, encoding: .utf8).replacingOccurrences(of: "CanonicalDecoder.decode", with: "JSONDecoder().decode"), to: path)
        #expect(try fixture.invoke().code == 0)
    }

    @Test func decoderAndCompositeDriftFailBeforeHistoricalChecks() throws {
        let fixture = try ParserFixture()
        let source = fixture.root.appendingPathComponent("Sources/MosaicEngine/Mosaic/Unexpected.swift")
        for content in ["CanonicalDecoder.decode\n", "JSONDecoder().decode\n"] {
            try write(content, to: source)
            let result = try fixture.invoke()
            #expect(result.code != 0)
            #expect(result.calls.isEmpty)
        }
        try FileManager.default.removeItem(at: source)
        let composite = fixture.root.appendingPathComponent(historicalPaths[0].replacingOccurrences(of: "Sources/OpalFusion/", with: "Sources/MosaicEngine/"))
        try write(try String(contentsOf: composite, encoding: .utf8) + "public static func openTransportBootstrapUnexpected() {}\n", to: composite)
        let result = try fixture.invoke()
        #expect(result.code != 0)
        #expect(result.calls.isEmpty)
    }
}
