// ElectronCashInteropEnvironmentError.swift

import Foundation

enum ElectronCashInteropEnvironmentError: LocalizedError, Equatable {
    case missing(String)
    case invalid(String, String)

    var errorDescription: String? {
        switch self {
        case let .missing(name):
            "Missing required interop environment variable \(name)"
        case let .invalid(name, summary):
            "Invalid value for \(name): \(summary)"
        }
    }
}
