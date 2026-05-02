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
        let coordinatorHost = try ElectronCashInteropTestSupport.requiredString(
            "OPALFUSION_EC_COORDINATOR_HOST",
            in: environment
        )
        let coordinatorPort = try ElectronCashInteropTestSupport.requiredUInt16(
            "OPALFUSION_EC_COORDINATOR_PORT",
            in: environment
        )
        let coordinatorRequiresTLS = try ElectronCashInteropTestSupport.parseOptionalBool(
            environment["OPALFUSION_EC_COORDINATOR_TLS"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            variableName: "OPALFUSION_EC_COORDINATOR_TLS"
        ) ?? false
        let genesisHash = try ElectronCashInteropTestSupport.requiredHexBytes(
            "OPALFUSION_EC_GENESIS_HASH_HEX",
            in: environment,
            expectedByteCount: 32
        )
        let joinTier = try ElectronCashInteropTestSupport.requiredUInt64(
            "OPALFUSION_EC_JOIN_TIER",
            in: environment
        )

        let inputTransactionHash = try ElectronCashInteropTestSupport.requiredHexBytes(
            "OPALFUSION_EC_INPUT_TXID_HEX",
            in: environment,
            expectedByteCount: 32
        )
        let inputIndex = try ElectronCashInteropTestSupport.requiredUInt32(
            "OPALFUSION_EC_INPUT_VOUT",
            in: environment
        )
        let inputAmountSatoshis = try ElectronCashInteropTestSupport.requiredUInt64(
            "OPALFUSION_EC_INPUT_AMOUNT_SATOSHIS",
            in: environment
        )
        let inputLockingScript = try ElectronCashInteropTestSupport.requiredHexBytes(
            "OPALFUSION_EC_INPUT_LOCKING_SCRIPT_HEX",
            in: environment
        )
        let participantInputPrivateKey = try ElectronCashInteropTestSupport.requiredHexBytes(
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

        let outputLockingScript = try ElectronCashInteropTestSupport.requiredHexBytes(
            "OPALFUSION_EC_OUTPUT_LOCKING_SCRIPT_HEX",
            in: environment
        )
        let outputAmountSatoshis = try ElectronCashInteropTestSupport.requiredUInt64(
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
            let torPort = try ElectronCashInteropTestSupport.parseUInt16(
                torPortString,
                variableName: "OPALFUSION_EC_TOR_SOCKS5_PORT"
            )
            let resolvesRemotely = try ElectronCashInteropTestSupport.parseOptionalBool(
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
