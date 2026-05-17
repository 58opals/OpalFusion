// LiveRuntimeTestSupportError.swift

enum LiveRuntimeTestSupportError: Swift.Error, Equatable {
    case timedOut(String)
    case missingTimeoutResult
    case missingConnection
    case inboundStreamClosed
    case invalidHTTPResponse(String)
    case signingInputNotFound
    case invalidTLSFixture(String)
}
