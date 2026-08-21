// ScriptedMosaicPrivateAlphaTorConnection.swift

import Foundation
@_spi(MosaicPrivateAlpha) import OpalFusion

actor ScriptedMosaicPrivateAlphaTorConnection:
    OpalFusion.MosaicPrivateAlphaRuntime.TorWebSocketConnection
{
    typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime

    private let stream: MessageStream
    private let continuation: MessageStream.Continuation
    private let eventAcceptance: Bool?
    private(set) var openCount = 0
    private(set) var closeCount = 0
    private(set) var sentTexts: [String] = []
    private var closeWaiter: CheckedContinuation<Void, Never>?

    init(eventAcceptance: Bool? = true) {
        self.eventAcceptance = eventAcceptance
        (stream, continuation) = MessageStream.makeStream()
    }

    func open(
        maximumIncomingMessageByteCount: Int
    ) async throws -> MessageStream {
        guard maximumIncomingMessageByteCount > 0 else {
            throw Runtime.Failure.invalidStateTransition
        }
        openCount += 1
        return stream
    }

    func send(text: String) async throws {
        sentTexts.append(text)
        let value = try JSONSerialization.jsonObject(with: Data(text.utf8))
        guard let message = value as? [Any],
              let messageType = message.first as? String else {
            throw Runtime.Failure.invalidStateTransition
        }
        switch messageType {
        case "EVENT":
            guard message.count == 2,
                  let object = message[1] as? [String: Any],
                  let identifier = object["id"] as? String else {
                throw Runtime.Failure.invalidStateTransition
            }
            guard let eventAcceptance else { return }
            let acknowledgement: [Any] = [
                "OK",
                identifier,
                eventAcceptance,
                "",
            ]
            let bytes = try JSONSerialization.data(
                withJSONObject: acknowledgement
            )
            continuation.yield(.text(bytes))

        case "REQ":
            guard message.count >= 3,
                  let identifier = message[1] as? String else {
                throw Runtime.Failure.invalidStateTransition
            }
            let endOfStoredEvents: [Any] = ["EOSE", identifier]
            let bytes = try JSONSerialization.data(
                withJSONObject: endOfStoredEvents
            )
            continuation.yield(.text(bytes))

        case "CLOSE":
            guard message.count == 2,
                  message[1] is String else {
                throw Runtime.Failure.invalidStateTransition
            }

        default:
            throw Runtime.Failure.invalidStateTransition
        }
    }

    func close() async {
        guard closeCount == 0 else { return }
        closeCount += 1
        continuation.finish()
        closeWaiter?.resume()
        closeWaiter = nil
    }

    func receive(_ message: Runtime.TorWebSocketMessage) {
        continuation.yield(message)
    }

    func waitUntilClosed() async {
        guard closeCount == 0 else { return }
        await withCheckedContinuation { continuation in
            closeWaiter = continuation
        }
    }
}
