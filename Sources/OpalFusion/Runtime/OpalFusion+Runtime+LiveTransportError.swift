// OpalFusion+Runtime+LiveTransportError.swift

import CFNetwork
import Foundation
import Network
import OSLog
import Security

extension OpalFusion.Runtime {
    enum LiveTransportError: LocalizedError, Sendable, Equatable {
        case invalidConfiguration(String)
        case primaryConnectionAlreadyStarted
        case primaryConnectionNotReady
        case primaryConnectionCancelled
        case covertEndpointNotPrepared
        case malformedCovertURL
        case covertPayloadTooLarge
        case invalidHTTPResponse
        case unexpectedHTTPStatus(Int)

        var errorDescription: String? {
            switch self {
            case let .invalidConfiguration(summary):
                summary
            case .primaryConnectionAlreadyStarted:
                "Primary connection was already started"
            case .primaryConnectionNotReady:
                "Primary connection is not ready"
            case .primaryConnectionCancelled:
                "Primary connection was cancelled"
            case .covertEndpointNotPrepared:
                "Covert endpoint was not prepared"
            case .malformedCovertURL:
                "Covert request URL could not be constructed"
            case .covertPayloadTooLarge:
                "Covert request payload exceeded the configured size limit"
            case .invalidHTTPResponse:
                "Covert request did not receive an HTTP response"
            case let .unexpectedHTTPStatus(statusCode):
                "Covert request failed with HTTP status \(statusCode)"
            }
        }
    }
}
