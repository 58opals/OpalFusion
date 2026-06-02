// ElectronCashTranscriptCaptureFormatter.swift

enum ElectronCashTranscriptCaptureFormatter {
    static let beginMarker = "-----BEGIN OPALFUSION ELECTRON CASH TRANSCRIPT CAPTURE-----"
    static let endMarker = "-----END OPALFUSION ELECTRON CASH TRANSCRIPT CAPTURE-----"

    static func markedSwiftFixtureCandidate(
        for capture: ElectronCashTranscriptCapture
    ) -> String {
        [
            beginMarker,
            swiftFixtureCandidate(for: capture),
            endMarker,
        ].joined(separator: "\n")
    }

    static func extractSwiftFixtureCandidate(from output: String) -> String? {
        let lines = output.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard let beginIndex = lines.firstIndex(of: beginMarker) else {
            return nil
        }

        let candidateStartIndex = lines.index(after: beginIndex)
        guard let endIndex = lines[candidateStartIndex...].firstIndex(of: endMarker) else {
            return nil
        }

        return lines[candidateStartIndex..<endIndex].joined(separator: "\n")
    }

    static func swiftFixtureCandidate(
        for capture: ElectronCashTranscriptCapture
    ) -> String {
        var lines: [String] = [
            "// ElectronCashPinnedTranscriptFixtures.swift",
            "",
            "// Captured from the env-gated Electron Cash interop smoke.",
            "// Baseline: Electron Cash 4.4.3-compatible CashFusion coordinator.",
            "// Capture date: <fill before committing fixture>.",
            "// Sensitive coordinator configuration and wallet material omitted.",
            "enum ElectronCashPinnedTranscriptFixtures {",
            "    static let baseline = \"Electron Cash 4.4.3-compatible CashFusion coordinator\"",
            "    static let captureShape = \"primary frames plus covert payloads\"",
            "    static let captureSource = \"env-gated interop smoke\"",
        ]

        appendByteSection(
            name: "primaryInboundChunks",
            values: capture.primaryInboundChunks,
            lines: &lines
        )
        appendByteSection(
            name: "primaryOutboundChunks",
            values: capture.primaryOutboundChunks,
            lines: &lines
        )
        appendByteSection(
            name: "covertRequestPayloads",
            values: capture.covertRequestPayloads,
            lines: &lines
        )
        appendByteSection(
            name: "covertResponsePayloads",
            values: capture.covertResponsePayloads,
            lines: &lines
        )
        appendStringSection(
            name: "clientMessageKinds",
            values: capture.clientMessageKinds,
            lines: &lines
        )
        appendStringSection(
            name: "serverMessageKinds",
            values: capture.serverMessageKinds,
            lines: &lines
        )
        appendStringSection(
            name: "covertMessageKinds",
            values: capture.covertMessageKinds,
            lines: &lines
        )
        appendStringSection(
            name: "covertResponseKinds",
            values: capture.covertResponseKinds,
            lines: &lines
        )
        appendStringSection(
            name: "roundOutcomes",
            values: capture.roundOutcomes,
            lines: &lines
        )
        appendStringSection(
            name: "eventSummaries",
            values: capture.eventSummaries,
            lines: &lines
        )

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private static func appendByteSection(
        name: String,
        values: [[UInt8]],
        lines: inout [String]
    ) {
        lines.append("")
        lines.append("    static let \(name): [[UInt8]] = [")
        for value in values {
            lines.append("        \(byteArrayLiteral(value)),")
        }
        lines.append("    ]")
    }

    private static func appendStringSection(
        name: String,
        values: [String],
        lines: inout [String]
    ) {
        lines.append("")
        lines.append("    static let \(name): [String] = [")
        for value in values {
            lines.append("        \"\(escaped(value))\",")
        }
        lines.append("    ]")
    }

    private static func byteArrayLiteral(_ bytes: [UInt8]) -> String {
        guard bytes.isEmpty == false else {
            return "[]"
        }
        return "[" + bytes.map(byteLiteral).joined(separator: ", ") + "]"
    }

    private static func byteLiteral(_ byte: UInt8) -> String {
        let digits = Array("0123456789ABCDEF")
        let high = digits[Int(byte >> 4)]
        let low = digits[Int(byte & 0x0F)]
        return "0x\(high)\(low)"
    }

    private static func escaped(_ string: String) -> String {
        var result = ""
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x08:
                result += "\\b"
            case 0x09:
                result += "\\t"
            case 0x0A:
                result += "\\n"
            case 0x0D:
                result += "\\r"
            case 0x22:
                result += "\\\""
            case 0x5C:
                result += "\\\\"
            case 0x20 ... 0x7E:
                result.unicodeScalars.append(scalar)
            default:
                result += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
            }
        }
        return result
    }
}
