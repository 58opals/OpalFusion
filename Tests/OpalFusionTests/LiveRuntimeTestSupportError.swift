// LiveRuntimeTestSupportError.swift

enum LiveRuntimeTestSupportError: Swift.Error, Equatable {
    case timedOut(String)
    case missingConnection
    case inboundStreamClosed
    case signingInputNotFound
    case invalidTLSFixture(String)
}
