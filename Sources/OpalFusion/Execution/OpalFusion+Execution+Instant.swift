// OpalFusion+Execution+Instant.swift

import Foundation

extension OpalFusion.Execution {
    struct Instant: Sendable, Equatable, Comparable {
        let millisecondsSinceUnixEpoch: Int64

        init(millisecondsSinceUnixEpoch: Int64) {
            self.millisecondsSinceUnixEpoch = millisecondsSinceUnixEpoch
        }

        init(unixSeconds: UInt64) {
            guard let instant = Self(validatingUnixSeconds: unixSeconds) else {
                self.init(millisecondsSinceUnixEpoch: Int64.max)
                return
            }

            self = instant
        }

        init?(validatingUnixSeconds unixSeconds: UInt64) {
            guard unixSeconds <= UInt64(Int64.max / 1_000) else {
                return nil
            }
            self.init(millisecondsSinceUnixEpoch: Int64(unixSeconds) * 1_000)
        }

        var unixSeconds: Int64 {
            millisecondsSinceUnixEpoch / 1_000
        }

        static var current: Self {
            .init(
                millisecondsSinceUnixEpoch: Int64((Date().timeIntervalSince1970 * 1_000).rounded())
            )
        }

        func advanced(by duration: Duration) -> Self {
            let deltaMilliseconds = duration.wholeMilliseconds
            let (advancedMilliseconds, overflow) = millisecondsSinceUnixEpoch
                .addingReportingOverflow(deltaMilliseconds)
            guard overflow == false else {
                return .init(
                    millisecondsSinceUnixEpoch: deltaMilliseconds >= 0 ? Int64.max : Int64.min
                )
            }
            return .init(
                millisecondsSinceUnixEpoch: advancedMilliseconds
            )
        }

        func distance(to other: Self) -> Duration {
            let (distanceMilliseconds, overflow) = other.millisecondsSinceUnixEpoch
                .subtractingReportingOverflow(millisecondsSinceUnixEpoch)
            guard overflow == false else {
                return .milliseconds(other >= self ? Int64.max : Int64.min)
            }
            return .milliseconds(distanceMilliseconds)
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.millisecondsSinceUnixEpoch < rhs.millisecondsSinceUnixEpoch
        }
    }
}
