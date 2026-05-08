// Duration+OpalFusionMillisecondsRoundedUp.swift

import Foundation

extension Duration {
    var opalFusionMillisecondsRoundedUp: Int {
        let components = components
        let secondsMilliseconds = Self.opalFusionClampedMilliseconds(
            fromSeconds: components.seconds
        )
        let attosecondsMilliseconds = Self.opalFusionRoundedUpMilliseconds(
            fromAttoseconds: components.attoseconds
        )
        let (milliseconds, overflow) = secondsMilliseconds.addingReportingOverflow(
            attosecondsMilliseconds
        )
        guard overflow == false else {
            return secondsMilliseconds >= 0 ? Int.max : Int.min
        }

        return Int(clamping: milliseconds)
    }

    private static func opalFusionClampedMilliseconds(
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

    private static func opalFusionRoundedUpMilliseconds(
        fromAttoseconds attoseconds: Int64
    ) -> Int64 {
        let attosecondsPerMillisecond: Int64 = 1_000_000_000_000_000
        guard attoseconds >= 0 else {
            let quotient = attoseconds / attosecondsPerMillisecond
            let remainder = attoseconds % attosecondsPerMillisecond
            return remainder == 0 ? quotient : quotient - 1
        }

        guard attoseconds > 0 else {
            return 0
        }

        return (attoseconds + attosecondsPerMillisecond - 1) / attosecondsPerMillisecond
    }
}
