// OpalDiagnostics+TraceID+OpalFusion.swift

import Foundation
import OpalDiagnostics

extension OpalDiagnostics.TraceID {
    static func opalFusionRound(
        _ roundIdentifier: OpalFusion.Round.Identifier?
    ) -> OpalDiagnostics.TraceID? {
        guard let roundIdentifier else {
            return nil
        }

        return OpalDiagnostics.TraceID(rawValue: roundIdentifier.rawValue)
    }
}
