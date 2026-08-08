// OpalFusion+Mosaic+NIP01RelaySession.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic {
    /// Correlates one NIP-01 relay connection without defining a concrete network route.
    ///
    /// The injected connection must already guarantee Tor-only routing. This actor performs no
    /// reconnect or fallback and treats malformed, unsolicited, or binary input as terminal.
    actor NIP01RelaySession {
        typealias Nostr = OpalFusion.Mosaic.NostrNamespace
        typealias OutputStream = AsyncThrowingStream<
            Nostr.RelayServerMessage,
            Swift.Error
        >

        private let connection: any TorWebSocketConnectioning
        private let codingLimits: Nostr.RelayMessageCodingLimits
        private let outputStream: OutputStream
        private var outputContinuation: OutputStream.Continuation
        private var inputTask: Task<Void, Never>?
        private var activeSubscriptions: Set<Nostr.SubscriptionIdentifier> = []
        private var publicationIdentifiers: [OpalCrypto.Signature.Digest] = []
        private var pendingPublications: [OpalCrypto.Signature.Digest] = []

        private(set) var state: State = .idle

        init(
            connection: any TorWebSocketConnectioning,
            codingLimits: Nostr.RelayMessageCodingLimits,
            maximumPendingOutputCount: Int
        ) throws {
            guard maximumPendingOutputCount > 0 else {
                throw Failure.invalidOutputBufferLimit
            }
            let (stream, continuation) = OutputStream.makeStream(
                bufferingPolicy: .bufferingOldest(maximumPendingOutputCount)
            )
            self.connection = connection
            self.codingLimits = codingLimits
            self.outputStream = stream
            self.outputContinuation = continuation
        }

        /// Opens the connection once and returns its single typed output stream.
        func start() async throws -> OutputStream {
            guard state == .idle else {
                throw Failure.alreadyStarted
            }
            state = .opening
            let messages: TorWebSocketConnectioning.MessageStream
            do {
                messages = try await connection.open(
                    maximumIncomingMessageByteCount: codingLimits.maximumFrameByteCount
                )
            } catch {
                guard state == .opening else {
                    throw Failure.notRunning
                }
                await finish(.failed(.transportFailure))
                throw Failure.transportFailure
            }
            guard state == .opening else {
                throw Failure.notRunning
            }
            state = .running
            outputContinuation.onTermination = { [weak self] termination in
                guard case .cancelled = termination else { return }
                Task { await self?.stop() }
            }
            inputTask = Task { [weak self] in
                await self?.consumeInput(messages)
            }
            return outputStream
        }

        func subscribe(_ subscription: Nostr.RelaySubscription) async throws {
            try requireRunning()
            guard activeSubscriptions.insert(subscription.identifier).inserted else {
                throw Failure.duplicateSubscription(subscription.identifier)
            }
            do {
                try await send(.request(subscription))
            } catch {
                activeSubscriptions.remove(subscription.identifier)
                throw error
            }
        }

        func closeSubscription(
            _ identifier: Nostr.SubscriptionIdentifier
        ) async throws {
            try requireRunning()
            guard activeSubscriptions.contains(identifier) else {
                throw Failure.unknownSubscription(identifier)
            }
            try await send(.close(identifier))
            activeSubscriptions.remove(identifier)
        }

        func publish(_ event: Nostr.Event) async throws {
            try requireRunning()
            guard !publicationIdentifiers.contains(event.identifier) else {
                throw Failure.duplicatePublication
            }
            publicationIdentifiers.append(event.identifier)
            pendingPublications.append(event.identifier)
            do {
                try await send(.event(event))
            } catch {
                publicationIdentifiers.removeAll { $0 == event.identifier }
                pendingPublications.removeAll { $0 == event.identifier }
                throw error
            }
        }

        /// Stops once, closes the injected connection, and never reconnects.
        func stop() async {
            guard case .terminal = state else {
                inputTask?.cancel()
                await finish(.stopped)
                return
            }
        }

        func waitForTermination() async {
            let inputTask = inputTask
            await inputTask?.value
        }

        private func consumeInput(
            _ messages: TorWebSocketConnectioning.MessageStream
        ) async {
            do {
                for try await message in messages {
                    try Task.checkCancellation()
                    try handle(message)
                }
                guard !Task.isCancelled else { return }
                await finish(.inputEnded)
            } catch is CancellationError {
                // Explicit stop owns terminalization and connection closure.
            } catch let failure as Failure {
                await finish(.failed(failure))
            } catch {
                await finish(.failed(.transportFailure))
            }
        }

        private func handle(_ message: TorWebSocketMessage) throws {
            let relayMessage: Nostr.RelayServerMessage
            switch message {
            case let .text(data):
                do {
                    relayMessage = try Nostr.RelayMessageCodec.decodeServerMessage(
                        data,
                        limits: codingLimits
                    )
                } catch {
                    throw Failure.malformedRelayFrame
                }
            case .binary:
                throw Failure.binaryFrameReceived
            }

            switch relayMessage {
            case let .event(subscription, _),
                 let .endOfStoredEvents(subscription):
                guard activeSubscriptions.contains(subscription) else {
                    throw Failure.unknownSubscription(subscription)
                }

            case let .subscriptionClosed(identifier, _):
                guard activeSubscriptions.remove(identifier) != nil else {
                    throw Failure.unknownSubscription(identifier)
                }

            case let .acknowledgement(eventIdentifier, _, _):
                guard let index = pendingPublications.firstIndex(of: eventIdentifier) else {
                    throw Failure.unsolicitedAcknowledgement
                }
                pendingPublications.remove(at: index)

            case .notice:
                break
            }

            switch outputContinuation.yield(relayMessage) {
            case .enqueued:
                break
            case .dropped:
                throw Failure.outputBufferOverflow
            case .terminated:
                throw CancellationError()
            @unknown default:
                throw Failure.outputBufferOverflow
            }
        }

        private func send(_ message: Nostr.RelayClientMessage) async throws {
            let data: Data
            do {
                data = try Nostr.RelayMessageCodec.encode(
                    message,
                    limits: codingLimits
                )
            } catch {
                await finish(.failed(.malformedRelayFrame))
                throw Failure.malformedRelayFrame
            }
            do {
                try await connection.send(text: String(decoding: data, as: UTF8.self))
            } catch {
                guard state == .running else {
                    throw Failure.notRunning
                }
                await finish(.failed(.transportFailure))
                throw Failure.transportFailure
            }
            try requireRunning()
        }

        private func requireRunning() throws {
            guard state == .running else {
                throw Failure.notRunning
            }
        }

        private func finish(_ termination: Termination) async {
            guard case .terminal = state else {
                state = .terminal(termination)
                activeSubscriptions.removeAll()
                publicationIdentifiers.removeAll()
                pendingPublications.removeAll()
                await connection.close()
                switch termination {
                case let .failed(failure):
                    outputContinuation.finish(throwing: failure)
                case .stopped, .inputEnded:
                    outputContinuation.finish()
                }
                return
            }
        }
    }
}
