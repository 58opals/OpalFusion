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

        init?(validatingUnixSeconds unixSeconds: UInt64) {
            guard unixSeconds <= UInt64(Int64.max / 1_000) else {
                return nil
            }
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

extension Duration {
    var wholeMilliseconds: Int64 {
        let components = self.components
        let secondsMilliseconds = Self.opalFusionClampedWholeMilliseconds(
            fromSeconds: components.seconds
        )
        let attosecondsMilliseconds = Self.opalFusionWholeMilliseconds(
            fromAttoseconds: components.attoseconds
        )
        let (milliseconds, overflow) = secondsMilliseconds.addingReportingOverflow(
            attosecondsMilliseconds
        )
        guard overflow == false else {
            return secondsMilliseconds >= 0 ? Int64.max : Int64.min
        }
        return milliseconds
    }

    private static func opalFusionClampedWholeMilliseconds(
        fromSeconds seconds: Int64
    ) -> Int64 {
        let multiplier: Int64 = 1_000
        guard seconds <= Int64.max / multiplier else {
            return Int64.max
        }
        guard seconds >= Int64.min / multiplier else {
            return Int64.min
        }
        return seconds * multiplier
    }

    private static func opalFusionWholeMilliseconds(
        fromAttoseconds attoseconds: Int64
    ) -> Int64 {
        let attosecondsPerMillisecond: Int64 = 1_000_000_000_000_000
        return attoseconds / attosecondsPerMillisecond
    }
}
