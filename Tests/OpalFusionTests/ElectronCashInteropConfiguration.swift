// ElectronCashInteropConfiguration.swift

@testable import OpalFusion
import Foundation
import OpalCrypto

struct ElectronCashInteropConfiguration: Sendable {
    let clientConfiguration: OpalFusion.Client.Configuration
    let genesisHash: [UInt8]
    let joinPools: OpalFusion.ProtocolModel.JoinPools
    let participantReservation: OpalFusion.Host.ParticipantReservation
    let participantInputPrivateKey: [UInt8]

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ElectronCashInteropConfiguration {
        let coordinatorHost = try ElectronCashInteropEnvironmentParser.requiredString(
            "OPALFUSION_EC_COORDINATOR_HOST",
            in: environment
        )
        let coordinatorPort = try ElectronCashInteropEnvironmentParser.requiredUInt16(
            "OPALFUSION_EC_COORDINATOR_PORT",
            in: environment
        )
        let coordinatorRequiresTLS = try ElectronCashInteropEnvironmentParser.parseOptionalBool(
            environment["OPALFUSION_EC_COORDINATOR_TLS"],
            environmentVariableName: "OPALFUSION_EC_COORDINATOR_TLS"
        ) ?? false
        let genesisHash = try ElectronCashInteropEnvironmentParser.requiredHexBytes(
            "OPALFUSION_EC_GENESIS_HASH_HEX",
            in: environment,
            expectedByteCount: 32
        )
        let joinTier = try ElectronCashInteropEnvironmentParser.requiredUInt64(
            "OPALFUSION_EC_JOIN_TIER",
            in: environment
        )

        let inputTransactionHash = try ElectronCashInteropEnvironmentParser.requiredHexBytes(
            "OPALFUSION_EC_INPUT_TXID_HEX",
            in: environment,
            expectedByteCount: 32
        )
        let inputIndex = try ElectronCashInteropEnvironmentParser.requiredUInt32(
            "OPALFUSION_EC_INPUT_VOUT",
            in: environment
        )
        let inputAmountSatoshis = try ElectronCashInteropEnvironmentParser.requiredUInt64(
            "OPALFUSION_EC_INPUT_AMOUNT_SATOSHIS",
            in: environment
        )
        let inputLockingScript = try ElectronCashInteropEnvironmentParser.requiredHexBytes(
            "OPALFUSION_EC_INPUT_LOCKING_SCRIPT_HEX",
            in: environment
        )
        let participantInputPrivateKey = try ElectronCashInteropEnvironmentParser.requiredHexBytes(
            "OPALFUSION_EC_INPUT_PRIVATE_KEY_HEX",
            in: environment,
            expectedByteCount: 32
        )
        let participantInputPublicKey = try Array(
            OpalCrypto.Secp256k1.derivePublicKey(
                from: OpalCrypto.Secp256k1.PrivateKey(
                    rawRepresentation: Data(participantInputPrivateKey)
                )
            ).rawRepresentation
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

        let outputLockingScript = try ElectronCashInteropEnvironmentParser.requiredHexBytes(
            "OPALFUSION_EC_OUTPUT_LOCKING_SCRIPT_HEX",
            in: environment
        )
        let outputAmountSatoshis = try ElectronCashInteropEnvironmentParser.requiredUInt64(
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
        let hasTorPortSetting = torPortString?.isEmpty == false
        let torRemoteResolutionString = environment["OPALFUSION_EC_TOR_REMOTE_RESOLUTION"]
        let hasTorRemoteResolutionSetting = torRemoteResolutionString?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false

        if let torHost, torHost.isEmpty == false {
            guard let torPortString, torPortString.isEmpty == false else {
                throw ElectronCashInteropEnvironmentError.missing(
                    "OPALFUSION_EC_TOR_SOCKS5_PORT"
                )
            }
            let torPort = try ElectronCashInteropEnvironmentParser.parseUInt16(
                torPortString,
                environmentVariableName: "OPALFUSION_EC_TOR_SOCKS5_PORT"
            )
            let resolvesRemotely = try ElectronCashInteropEnvironmentParser.parseOptionalBool(
                torRemoteResolutionString,
                environmentVariableName: "OPALFUSION_EC_TOR_REMOTE_RESOLUTION"
            ) ?? true
            torSocks5 = .init(
                host: torHost,
                port: torPort,
                resolvesCoordinatorHostNameRemotely: resolvesRemotely
            )
        } else if hasTorPortSetting || hasTorRemoteResolutionSetting {
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
