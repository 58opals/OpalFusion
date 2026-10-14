// LiveRuntimeTestHarnessError.swift

enum LiveRuntimeTestHarnessError: Swift.Error, Equatable {
    case timedOut(String)
    case missingTimeoutResult
    case missingConnection
    case inboundStreamClosed
    case invalidLoopbackPort(UInt16)
    case invalidFragmentLength(Int)
    case signingInputNotFound
    case invalidTLSFixture(String)
}
