import CryptoKit
import Foundation
import Testing

struct ReferenceFixtureProvenanceTests {
    @Test("Preserve the independently requalified RFC 9500 testRSA2048 artifact")
    func validatePublishedTestKeyIdentity() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../..")
        let sourceURL = root.appendingPathComponent(
            "Tests/Mosaic/Tests/MosaicEngineTests/RFC9500RSATestKeyFixture.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let pattern = #"\bprivate\s+static\s+let\s+privateKeyDERBase64\s*=\s*\"\"\"([\s\S]*?)\"\"\""#
        let expression = try NSRegularExpression(pattern: pattern)
        let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
        try #require(matches.count == 1)
        let range = try #require(Range(matches[0].range(at: 1), in: source))
        let literal = String(source[range])
        try #require(!literal.contains("\\"), "Fixture must contain no Swift escapes or interpolation")
        let base64 = literal.filter { ![" ", "\t", "\r", "\n"].contains($0) }
        let data = try #require(Data(base64Encoded: base64))
        #expect(data.count == 1_191)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "5882709c242c6f47cef05fb6a601322092635fd40c639d7548e4f488f4fbddf8")

        let document = try String(
            contentsOf: root.appendingPathComponent("docs/reference-fixture-provenance.md"),
            encoding: .utf8
        )
        #expect(document.contains("https://www.rfc-editor.org/rfc/rfc9500.txt"))
        #expect(document.contains("838d15624be54dc05b5b803d1b7e117f3e15ad34337e83c1b24e9ce7bf0f2a1a"))
        #expect(document.contains(digest))
    }
}
