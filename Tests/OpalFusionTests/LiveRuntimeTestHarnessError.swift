// LiveRuntimeTestHarnessError.swift

enum LiveRuntimeTestHarnessError: Swift.Error, Equatable {
    case timedOut(String)
    case missingTimeoutResult
    case missingConnection
    case inboundStreamClosed
    case invalidHTTPResponse(String)
    case signingInputNotFound
    case invalidTLSFixture(String)
}
