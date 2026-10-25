import Foundation

struct TimingEntry {
    let kind: String
    let name: String
    let outcome: String
    let seconds: Double
}

func timingEntries(_ contents: String) throws -> [TimingEntry] {
    let pattern = try regularExpression(#"(?m)\b(Test|Suite) (.+) (passed|failed) after ([0-9]+(?:\.[0-9]+)?) seconds\.\r?$"#)
    return try pattern.matches(in: contents, range: NSRange(contents.startIndex..., in: contents)).map { match in
        func field(_ index: Int) throws -> String {
            guard let range = Range(match.range(at: index), in: contents) else { throw ValidationFailure("Invalid timing record") }
            return String(contents[range])
        }
        guard let seconds = Double(try field(4)), seconds.isFinite else { throw ValidationFailure("Invalid timing duration") }
        return TimingEntry(kind: try field(1), name: try field(2), outcome: try field(3), seconds: seconds)
    }
}

func reportTimings(at url: URL, emit: (String) -> Void) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
          let size = attributes[.size] as? NSNumber, size.int64Value <= 64 * 1_024 * 1_024 else {
        throw ValidationFailure("Timing input must be a regular UTF-8 log no larger than 64 MiB")
    }
    let entries = try timingEntries(String(contentsOf: url, encoding: .utf8))
    guard !entries.isEmpty else { throw ValidationFailure("No completed Swift Testing timing records found") }
    emit("Historical timing analysis only; no tests executed and no current validation acceptance implied.")
    for entry in entries where entry.kind == "Test" && entry.name.hasPrefix("run with ") {
        emit(String(format: "Harness: %.3fs; %@; %@", entry.seconds, entry.outcome, entry.name))
    }
    for kind in ["Test", "Suite"] {
        emit("Slowest completed \(kind.lowercased()) records (reported wall time; overlapping records must not be summed):")
        let ordered = entries.filter { $0.kind == kind && !$0.name.hasPrefix("run with ") }.sorted {
            $0.seconds == $1.seconds ? $0.name < $1.name : $0.seconds > $1.seconds
        }
        for entry in ordered.prefix(10) {
            emit(String(format: "  %.3fs; %@; %@", entry.seconds, entry.outcome, entry.name))
        }
    }
    emit("Only completed records are ranked. An interrupted or truncated log cannot establish complete coverage or CPU attribution.")
}
