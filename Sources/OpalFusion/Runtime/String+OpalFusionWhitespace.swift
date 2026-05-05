// String+OpalFusionWhitespace.swift

import Foundation

extension String {
    var hasWhitespace: Bool {
        unicodeScalars.contains {
            CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }
}
