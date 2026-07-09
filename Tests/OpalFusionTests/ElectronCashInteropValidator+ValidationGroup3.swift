// ElectronCashInteropValidator+ValidationGroup3.swift

@testable import OpalFusion
import Foundation
import Testing

extension ElectronCashInteropValidator {
    func shouldEmitTranscriptCapture(
        snapshot: OpalFusion.Client.Session.Snapshot,
        hasExpectedClientMessages: Bool,
        hasExpectedServerMessages: Bool,
        hasExpectedCovertMessages: Bool,
        primaryOutboundDecodeFailures: [String],
        primaryInboundDecodeFailures: [String],
        covertRequestDecodeFailures: [String],
        covertResponseDecodeFailures: [String]
    ) -> Bool {
        ElectronCashInteropTestSupport.isTranscriptCaptureEnabled
            && snapshot.lastError == nil
            && snapshot.state.isConnected
            && snapshot.state.round?.completionStatus == .success
            && hasExpectedClientMessages
            && hasExpectedServerMessages
            && hasExpectedCovertMessages
            && primaryOutboundDecodeFailures.isEmpty
            && primaryInboundDecodeFailures.isEmpty
            && covertRequestDecodeFailures.isEmpty
            && covertResponseDecodeFailures.isEmpty
    }

    func makeMinimumInteropEnvironment() throws -> [String: String] {
        let scenario = try ProductionWorkflowTestFixtures.makeScenario()
        let input = try #require(scenario.reservation.inputs.first)
        let output = try #require(scenario.reservation.outputs.first)
        let genesisHash = try #require(PrimaryRuntimeTestFixtures.clientHello.genesisHash)

        return [
            "OPALFUSION_EC_COORDINATOR_HOST": "127.0.0.1",
            "OPALFUSION_EC_COORDINATOR_PORT": "50001",
            "OPALFUSION_EC_GENESIS_HASH_HEX": hexString(genesisHash),
            "OPALFUSION_EC_JOIN_TIER": "10000",
            "OPALFUSION_EC_INPUT_TXID_HEX": hexString(input.outpointTransactionHashBytes),
            "OPALFUSION_EC_INPUT_VOUT": "\(input.outpointIndex)",
            "OPALFUSION_EC_INPUT_AMOUNT_SATOSHIS": "\(input.amountSatoshis)",
            "OPALFUSION_EC_INPUT_LOCKING_SCRIPT_HEX": hexString(input.lockingScriptBytes),
            "OPALFUSION_EC_INPUT_PRIVATE_KEY_HEX": hexString(scenario.participantInputPrivateKey),
            "OPALFUSION_EC_OUTPUT_LOCKING_SCRIPT_HEX": hexString(output.lockingScriptBytes),
            "OPALFUSION_EC_OUTPUT_AMOUNT_SATOSHIS": "\(output.amountSatoshis)"
        ]
    }

    func hexString(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
