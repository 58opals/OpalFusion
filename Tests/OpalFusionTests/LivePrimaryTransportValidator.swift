// LivePrimaryTransportValidator.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

struct LivePrimaryTransportValidator {















}

extension LivePrimaryTransportValidator {
    static func makeScriptedTransport(
        _ factory: ScriptedNetworkPrimaryConnectionFixture,
        restartDelay: Duration = .milliseconds(100)
    ) -> OpalFusion.Runtime.LivePrimaryTransport {
        OpalFusion.Runtime.LivePrimaryTransport(
            host: "127.0.0.1",
            port: 8789,
            restartDelay: restartDelay,
            connectionFactory: { host, port, parameters in
                factory.make(
                    host: host,
                    port: port,
                    parameters: parameters
                )
            }
        )
    }

    static func expectLiveTransportError<Success>(
        _ expectedError: OpalFusion.Runtime.LiveTransportError,
        from operation: () async throws -> Success
    ) async {
        do {
            _ = try await operation()
            Issue.record("Expected \(expectedError)")
        } catch let error as OpalFusion.Runtime.LiveTransportError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected \(expectedError), received \(String(describing: error))")
        }
    }

    static func expectHarnessError<Success>(
        _ expectedDescription: String,
        from operation: () async throws -> Success,
        matching matches: (LiveRuntimeTestHarnessError) -> Bool
    ) async {
        do {
            _ = try await operation()
            Issue.record("Expected \(expectedDescription)")
        } catch let error as LiveRuntimeTestHarnessError {
            #expect(matches(error), "Expected \(expectedDescription), received \(error)")
        } catch {
            Issue.record("Expected \(expectedDescription), received \(String(describing: error))")
        }
    }

    static func expectPOSIXError(
        _ expectedCode: POSIXErrorCode,
        from error: any Error
    ) {
        guard let networkError = error as? NWError else {
            Issue.record("Expected NWError, received \(String(describing: error))")
            return
        }

        guard case let .posix(actualCode) = networkError else {
            Issue.record("Expected POSIX NWError, received \(String(describing: networkError))")
            return
        }

        #expect(actualCode == expectedCode)
    }
}
