// OpalFusion+Execution+Instant.swift

import Foundation

extension OpalFusion.Execution {
    struct Instant: Sendable, Equatable, Comparable {
        let millisecondsSinceUnixEpoch: Int64

        init(millisecondsSinceUnixEpoch: Int64) {
            self.millisecondsSinceUnixEpoch = millisecondsSinceUnixEpoch
        }

        init(unixSeconds: UInt64) {
            self.init(millisecondsSinceUnixEpoch: Int64(unixSeconds) * 1_000)
        }

        var unixSeconds: Int64 {
            millisecondsSinceUnixEpoch / 1_000
        }

        static func now() -> Self {
            .init(
                millisecondsSinceUnixEpoch: Int64((Date().timeIntervalSince1970 * 1_000).rounded())
            )
        }

        func advanced(by duration: Duration) -> Self {
            .init(
                millisecondsSinceUnixEpoch: millisecondsSinceUnixEpoch + duration.wholeMilliseconds
            )
        }

        func distance(to other: Self) -> Duration {
            .milliseconds(other.millisecondsSinceUnixEpoch - millisecondsSinceUnixEpoch)
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.millisecondsSinceUnixEpoch < rhs.millisecondsSinceUnixEpoch
        }
    }
}

extension Duration {
    var wholeMilliseconds: Int64 {
        let components = self.components
        let attosecondsPerMillisecond: Int64 = 1_000_000_000_000_000
        return (components.seconds * 1_000) + (components.attoseconds / attosecondsPerMillisecond)
    }
}
