// OpalFusion+Client+ReconnectPolicy.swift

import Foundation

public extension OpalFusion.Client {
    struct ReconnectPolicy: Sendable, Equatable {
        public let initialDelay: Duration
        public let maximumDelay: Duration
        public let multiplier: Double
        public let maximumAttempts: Int?

        public static let disabled = Self(
            initialDelay: .zero,
            maximumDelay: .zero,
            multiplier: 1,
            maximumAttempts: 0
        )

        public static let walletDefault = Self(
            initialDelay: .seconds(3),
            maximumDelay: .seconds(30),
            multiplier: 1.5,
            maximumAttempts: nil
        )

        public init(
            initialDelay: Duration,
            maximumDelay: Duration,
            multiplier: Double,
            maximumAttempts: Int?
        ) {
            precondition(
                initialDelay.opalFusionMillisecondsRoundedUp >= 0,
                "Reconnect initial delay must not be negative"
            )
            precondition(
                maximumDelay.opalFusionMillisecondsRoundedUp >= initialDelay.opalFusionMillisecondsRoundedUp,
                "Reconnect maximum delay must be greater than or equal to the initial delay"
            )
            precondition(
                multiplier.isFinite && multiplier >= 1,
                "Reconnect multiplier must be finite and greater than or equal to 1"
            )
            precondition(
                maximumAttempts == nil || maximumAttempts! >= 0,
                "Reconnect maximum attempts must not be negative"
            )

            self.initialDelay = initialDelay
            self.maximumDelay = maximumDelay
            self.multiplier = multiplier
            self.maximumAttempts = maximumAttempts
        }
    }
}

extension OpalFusion.Client.ReconnectPolicy {
    func calculateDelay(
        forRetryAttempt attempt: Int
    ) -> Duration? {
        guard maximumAttempts != 0, attempt > 0 else {
            return nil
        }

        let initialMilliseconds = initialDelay.opalFusionMillisecondsRoundedUp
        guard maximumAttempts != nil || initialMilliseconds > 0 else {
            return nil
        }

        if let maximumAttempts, attempt > maximumAttempts {
            return nil
        }

        let maximumMilliseconds = maximumDelay.opalFusionMillisecondsRoundedUp
        let multiplierExponent = Double(attempt - 1)
        let scaledMilliseconds = Double(initialMilliseconds) * pow(multiplier, multiplierExponent)
        guard scaledMilliseconds.isFinite,
              scaledMilliseconds < Double(maximumMilliseconds) else {
            return .milliseconds(maximumMilliseconds)
        }

        let clampedMilliseconds = Int(scaledMilliseconds.rounded(.up))

        return .milliseconds(clampedMilliseconds)
    }
}
