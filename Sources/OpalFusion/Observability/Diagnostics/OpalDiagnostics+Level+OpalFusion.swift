// OpalDiagnostics+Level+OpalFusion.swift

import Foundation
import OpalDiagnostics

extension OpalDiagnostics.Level {
    static func opalFusionDefault(for event: OpalDiagnostics.Event) -> OpalDiagnostics.Level {
        if event.rawValue.hasSuffix(".failed") || event == .transportError {
            return .error
        }

        if event.rawValue.hasSuffix(".completed") ||
            event.rawValue.hasSuffix(".entered") ||
            event.rawValue.hasSuffix(".restarted") ||
            event.rawValue.hasSuffix(".peer_eof") {
            return .notice
        }

        return .debug
    }
}
