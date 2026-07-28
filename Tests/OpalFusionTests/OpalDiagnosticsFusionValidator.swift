// OpalDiagnosticsFusionValidator.swift

@testable import OpalFusion
import Foundation
import Network
import OpalCrypto
import OpalDiagnostics
import Testing

@Suite(.serialized)
struct OpalDiagnosticsFusionValidator {





















    static let fastReconnectPolicy = OpalFusion.Client.ReconnectPolicy(
        initialDelay: .milliseconds(10),
        maximumDelay: .milliseconds(10),
        multiplier: 1,
        maximumAttempts: 1
    )

    static let diagnosticsConfiguration = OpalDiagnostics.Configuration(
        minimumLevel: .debug,
        categoryFilter: .enabledIncludingSubcategories([OpalDiagnostics.Category.fusion]),
        bufferPolicy: .enabled(capacity: 1_000)
    )

    static let primaryRoundTraceID = OpalDiagnostics.TraceID(
        publicValue: PrimaryRuntimeTestFixtures.roundIdentifier.rawValue
    )












}
