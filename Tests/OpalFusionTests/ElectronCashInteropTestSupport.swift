// ElectronCashInteropTestSupport.swift

@testable import OpalFusion
import Foundation
import OpalCrypto

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

struct ElectronCashInteropConfiguration: Sendable {
    let clientConfiguration: OpalFusion.Client.Configuration
    let genesisHash: [UInt8]
    let joinPools: OpalFusion.ProtocolModel.JoinPools
    let participantReservation: OpalFusion.Host.ParticipantReservation
    let participantInputPrivateKey: [UInt8]

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ElectronCashInteropConfiguration {
        let coordinatorHost = try requiredString(
            "OPALFUSION_EC_COORDINATOR_HOST",
            in: environment
        )
        let coordinatorPort = try requiredUInt16(
            "OPALFUSION_EC_COORDINATOR_PORT",
            in: environment
        )
        let coordinatorRequiresTLS = try parseOptionalBool(
            environment["OPALFUSION_EC_COORDINATOR_TLS"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            variableName: "OPALFUSION_EC_COORDINATOR_TLS"
        ) ?? false
        let genesisHash = try requiredHexBytes(
            "OPALFUSION_EC_GENESIS_HASH_HEX",
            in: environment,
            expectedByteCount: 32
        )
        let joinTier = try requiredUInt64(
            "OPALFUSION_EC_JOIN_TIER",
            in: environment
        )

        let inputTransactionHash = try requiredHexBytes(
            "OPALFUSION_EC_INPUT_TXID_HEX",
            in: environment,
            expectedByteCount: 32
        )
        let inputIndex = try requiredUInt32(
            "OPALFUSION_EC_INPUT_VOUT",
            in: environment
        )
        let inputAmountSatoshis = try requiredUInt64(
            "OPALFUSION_EC_INPUT_AMOUNT_SATOSHIS",
            in: environment
        )
        let inputLockingScript = try requiredHexBytes(
            "OPALFUSION_EC_INPUT_LOCKING_SCRIPT_HEX",
            in: environment
        )
        let participantInputPrivateKey = try requiredHexBytes(
            "OPALFUSION_EC_INPUT_PRIVATE_KEY_HEX",
            in: environment,
            expectedByteCount: 32
        )
        let participantInputPublicKey = try Array(
            OpalCrypto.Signature.derivePublicKey(
                fromPrivateKey: Data(participantInputPrivateKey)
            )
        )
        guard OpalFusion.Execution.ProtocolPrimitives.isStandardP2PKHLockingScript(
            inputLockingScript,
            publicKey: participantInputPublicKey
        ) else {
            throw ElectronCashInteropEnvironmentError.invalid(
                "OPALFUSION_EC_INPUT_LOCKING_SCRIPT_HEX",
                "must be a standard compressed-key P2PKH locking script matching OPALFUSION_EC_INPUT_PRIVATE_KEY_HEX"
            )
        }

        let outputLockingScript = try requiredHexBytes(
            "OPALFUSION_EC_OUTPUT_LOCKING_SCRIPT_HEX",
            in: environment
        )
        let outputAmountSatoshis = try requiredUInt64(
            "OPALFUSION_EC_OUTPUT_AMOUNT_SATOSHIS",
            in: environment
        )

        let participantReservation = OpalFusion.Host.ParticipantReservation(
            inputs: [
                .init(
                    outpointTransactionHashBytes: inputTransactionHash,
                    outpointIndex: inputIndex,
                    amountSatoshis: inputAmountSatoshis,
                    lockingScriptBytes: inputLockingScript,
                    publicKey: participantInputPublicKey
                )
            ],
            outputs: [
                .init(
                    lockingScriptBytes: outputLockingScript,
                    amountSatoshis: outputAmountSatoshis
                )
            ]
        )

        let torSocks5: OpalFusion.Transport.TorSocks5Configuration?
        let torHost = environment["OPALFUSION_EC_TOR_SOCKS5_HOST"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let torPortString = environment["OPALFUSION_EC_TOR_SOCKS5_PORT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let torRemoteResolutionString = environment["OPALFUSION_EC_TOR_REMOTE_RESOLUTION"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let torHost, torHost.isEmpty == false {
            guard let torPortString, torPortString.isEmpty == false else {
                throw ElectronCashInteropEnvironmentError.missing(
                    "OPALFUSION_EC_TOR_SOCKS5_PORT"
                )
            }
            let torPort = try parseUInt16(
                torPortString,
                variableName: "OPALFUSION_EC_TOR_SOCKS5_PORT"
            )
            let resolvesRemotely = try parseOptionalBool(
                torRemoteResolutionString,
                variableName: "OPALFUSION_EC_TOR_REMOTE_RESOLUTION"
            ) ?? true
            torSocks5 = .init(
                host: torHost,
                port: torPort,
                resolvesCoordinatorHostNameRemotely: resolvesRemotely
            )
        } else if torPortString != nil || torRemoteResolutionString != nil {
            throw ElectronCashInteropEnvironmentError.missing(
                "OPALFUSION_EC_TOR_SOCKS5_HOST"
            )
        } else {
            torSocks5 = nil
        }

        return .init(
            clientConfiguration: .init(
                coordinatorHost: coordinatorHost,
                coordinatorPort: coordinatorPort,
                coordinatorRequiresTLS: coordinatorRequiresTLS,
                covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel,
                torSocks5: torSocks5
            ),
            genesisHash: genesisHash,
            joinPools: .init(
                tiers: [joinTier],
                tags: []
            ),
            participantReservation: participantReservation,
            participantInputPrivateKey: participantInputPrivateKey
        )
    }
}

actor RecordingPrimaryTransport: OpalFusion.Runtime.PrimaryTransporting {
    private let base: any OpalFusion.Runtime.PrimaryTransporting
    private var outboundFrameDecoder: OpalFusion.Wire.PrimaryFrameDecoder
    private var inboundFrameDecoder: OpalFusion.Wire.PrimaryFrameDecoder
    private let messageDecoder: OpalFusion.Wire.PrimaryMessageDecoder
    private(set) var clientMessages: [OpalFusion.ProtocolModel.ClientMessage]
    private(set) var serverMessages: [OpalFusion.ProtocolModel.ServerMessage]
    private(set) var outboundDecodeFailures: [String]
    private(set) var inboundDecodeFailures: [String]

    init(
        base: any OpalFusion.Runtime.PrimaryTransporting,
        baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443
    ) {
        self.base = base
        self.outboundFrameDecoder = .init(configuration: baseline.framing)
        self.inboundFrameDecoder = .init(configuration: baseline.framing)
        self.messageDecoder = .init()
        self.clientMessages = []
        self.serverMessages = []
        self.outboundDecodeFailures = []
        self.inboundDecodeFailures = []
    }

    func connect() async throws -> AsyncThrowingStream<[UInt8], Error> {
        let inboundStream = try await base.connect()
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: [UInt8].self,
            throwing: Error.self
        )

        Task {
            do {
                for try await bytes in inboundStream {
                    self.recordInbound(bytes)
                    continuation.yield(bytes)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        return stream
    }

    func write(_ bytes: [UInt8]) async throws {
        try await base.write(bytes)
        recordOutbound(bytes)
    }

    func close() async {
        await base.close()
    }

    private func recordOutbound(_ bytes: [UInt8]) {
        do {
            let payloads = try outboundFrameDecoder.append(bytes)
            for payload in payloads {
                clientMessages.append(try messageDecoder.decodeClient(payload))
            }
        } catch {
            outboundDecodeFailures.append(String(describing: error))
        }
    }

    private func recordInbound(_ bytes: [UInt8]) {
        do {
            let payloads = try inboundFrameDecoder.append(bytes)
            for payload in payloads {
                serverMessages.append(try messageDecoder.decodeServer(payload))
            }
        } catch {
            inboundDecodeFailures.append(String(describing: error))
        }
    }

    func recordedClientMessages() -> [OpalFusion.ProtocolModel.ClientMessage] {
        clientMessages
    }

    func recordedServerMessages() -> [OpalFusion.ProtocolModel.ServerMessage] {
        serverMessages
    }

    func recordedOutboundDecodeFailures() -> [String] {
        outboundDecodeFailures
    }

    func recordedInboundDecodeFailures() -> [String] {
        inboundDecodeFailures
    }
}

actor RecordingCovertTransport: OpalFusion.Runtime.CovertTransporting {
    private let base: any OpalFusion.Runtime.CovertTransporting
    private let messageDecoder: OpalFusion.Wire.CovertMessageDecoder
    private(set) var preparationPlans: [OpalFusion.Runtime.CovertPreparationPlan]
    private(set) var requests: [OpalFusion.Runtime.CovertRequest]
    private(set) var requestMessages: [OpalFusion.ProtocolModel.CovertMessage]
    private(set) var responses: [OpalFusion.ProtocolModel.CovertResponse]
    private(set) var requestDecodeFailures: [String]
    private(set) var responseDecodeFailures: [String]

    init(base: any OpalFusion.Runtime.CovertTransporting) {
        self.base = base
        self.messageDecoder = .init()
        self.preparationPlans = []
        self.requests = []
        self.requestMessages = []
        self.responses = []
        self.requestDecodeFailures = []
        self.responseDecodeFailures = []
    }

    func prepare(_ plan: OpalFusion.Runtime.CovertPreparationPlan) async throws {
        try await base.prepare(plan)
        preparationPlans.append(plan)
    }

    func perform(_ request: OpalFusion.Runtime.CovertRequest) async throws -> [UInt8] {
        requests.append(request)
        do {
            requestMessages.append(try messageDecoder.decodeMessage(request.payload))
        } catch {
            requestDecodeFailures.append(String(describing: error))
        }

        let responseBytes = try await base.perform(request)
        do {
            responses.append(try messageDecoder.decodeResponse(responseBytes))
        } catch {
            responseDecodeFailures.append(String(describing: error))
        }
        return responseBytes
    }

    func reset() async {
        await base.reset()
    }

    func recordedPreparationPlans() -> [OpalFusion.Runtime.CovertPreparationPlan] {
        preparationPlans
    }

    func recordedRequests() -> [OpalFusion.Runtime.CovertRequest] {
        requests
    }

    func recordedRequestMessages() -> [OpalFusion.ProtocolModel.CovertMessage] {
        requestMessages
    }

    func recordedResponses() -> [OpalFusion.ProtocolModel.CovertResponse] {
        responses
    }

    func recordedRequestDecodeFailures() -> [String] {
        requestDecodeFailures
    }

    func recordedResponseDecodeFailures() -> [String] {
        responseDecodeFailures
    }
}

private func requiredString(
    _ name: String,
    in environment: [String: String]
) throws -> String {
    guard let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
          value.isEmpty == false else {
        throw ElectronCashInteropEnvironmentError.missing(name)
    }
    return value
}

private func requiredUInt16(
    _ name: String,
    in environment: [String: String]
) throws -> UInt16 {
    try parseUInt16(
        requiredString(name, in: environment),
        variableName: name
    )
}

private func requiredUInt32(
    _ name: String,
    in environment: [String: String]
) throws -> UInt32 {
    try parseUInt32(
        requiredString(name, in: environment),
        variableName: name
    )
}

private func requiredUInt64(
    _ name: String,
    in environment: [String: String]
) throws -> UInt64 {
    try parseUInt64(
        requiredString(name, in: environment),
        variableName: name
    )
}

private func requiredHexBytes(
    _ name: String,
    in environment: [String: String],
    expectedByteCount: Int? = nil
) throws -> [UInt8] {
    let bytes = try parseHexBytes(
        requiredString(name, in: environment),
        variableName: name
    )
    if let expectedByteCount, bytes.count != expectedByteCount {
        throw ElectronCashInteropEnvironmentError.invalid(
            name,
            "expected \(expectedByteCount) bytes but received \(bytes.count)"
        )
    }
    return bytes
}

private func parseUInt16(
    _ value: String,
    variableName: String
) throws -> UInt16 {
    guard let parsedValue = UInt16(value) else {
        throw ElectronCashInteropEnvironmentError.invalid(
            variableName,
            "expected an unsigned 16-bit integer"
        )
    }
    return parsedValue
}

private func parseUInt32(
    _ value: String,
    variableName: String
) throws -> UInt32 {
    guard let parsedValue = UInt32(value) else {
        throw ElectronCashInteropEnvironmentError.invalid(
            variableName,
            "expected an unsigned 32-bit integer"
        )
    }
    return parsedValue
}

private func parseUInt64(
    _ value: String,
    variableName: String
) throws -> UInt64 {
    guard let parsedValue = UInt64(value) else {
        throw ElectronCashInteropEnvironmentError.invalid(
            variableName,
            "expected an unsigned 64-bit integer"
        )
    }
    return parsedValue
}

private func parseOptionalBool(
    _ value: String?,
    variableName: String
) throws -> Bool? {
    guard let value, value.isEmpty == false else {
        return nil
    }

    switch value.lowercased() {
    case "1", "true", "yes", "on":
        return true
    case "0", "false", "no", "off":
        return false
    default:
        throw ElectronCashInteropEnvironmentError.invalid(
            variableName,
            "expected one of 1, 0, true, false, yes, or no"
        )
    }
}

private func parseHexBytes(
    _ value: String,
    variableName: String
) throws -> [UInt8] {
    let trimmedValue = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let normalizedValue: String
    if trimmedValue.hasPrefix("0x") {
        normalizedValue = String(trimmedValue.dropFirst(2))
    } else {
        normalizedValue = trimmedValue
    }

    guard normalizedValue.isEmpty == false else {
        throw ElectronCashInteropEnvironmentError.invalid(
            variableName,
            "hex string must not be empty"
        )
    }
    guard normalizedValue.count.isMultiple(of: 2) else {
        throw ElectronCashInteropEnvironmentError.invalid(
            variableName,
            "hex string must have an even number of characters"
        )
    }

    var bytes: [UInt8] = []
    bytes.reserveCapacity(normalizedValue.count / 2)

    var cursor = normalizedValue.startIndex
    while cursor < normalizedValue.endIndex {
        let nextCursor = normalizedValue.index(cursor, offsetBy: 2)
        let byteString = normalizedValue[cursor..<nextCursor]
        guard let byte = UInt8(byteString, radix: 16) else {
            throw ElectronCashInteropEnvironmentError.invalid(
                variableName,
                "hex string contained non-hex characters"
            )
        }
        bytes.append(byte)
        cursor = nextCursor
    }

    return bytes
}
