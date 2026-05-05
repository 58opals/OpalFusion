// Duration+OpalFusionWholeMilliseconds.swift

import Foundation

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
