// ElectronCashInteropValidator+ValidationGroup1.swift

@testable import OpalFusion
import Foundation
import Testing

extension ElectronCashInteropValidator {
    @Test("Electron Cash interop optional boolean parser trims whitespace")
    func validateOptionalBooleanParserTrimsWhitespace() throws {
        #expect(
            try ElectronCashInteropEnvironmentParser.parseOptionalBool(
                " true ",
                environmentVariableName: "OPALFUSION_EC_COORDINATOR_TLS"
            ) == true
        )
        #expect(
            try ElectronCashInteropEnvironmentParser.parseOptionalBool(
                "\n0\t",
                environmentVariableName: "OPALFUSION_EC_TOR_REMOTE_RESOLUTION"
            ) == false
        )
        #expect(
            try ElectronCashInteropEnvironmentParser.parseOptionalBool(
                "   ",
                environmentVariableName: "OPALFUSION_EC_TOR_REMOTE_RESOLUTION"
            ) == nil
        )
    }

    @Test("Electron Cash interop numeric parser trims whitespace")
    func validateNumericParserTrimsWhitespace() throws {
        #expect(
            try ElectronCashInteropEnvironmentParser.parseUInt16(
                " 50001 ",
                environmentVariableName: "OPALFUSION_EC_COORDINATOR_PORT"
            ) == 50_001
        )
        #expect(
            try ElectronCashInteropEnvironmentParser.parseUInt32(
                "\n1\t",
                environmentVariableName: "OPALFUSION_EC_INPUT_INDEX"
            ) == 1
        )
        #expect(
            try ElectronCashInteropEnvironmentParser.parseUInt64(
                " 100000 ",
                environmentVariableName: "OPALFUSION_EC_JOIN_TIER"
            ) == 100_000
        )
    }

    @Test("Electron Cash interop ignores blank optional Tor settings")
    func validateBlankOptionalTorSettingsAreIgnored() throws {
        var environment = try makeMinimumInteropEnvironment()
        environment["OPALFUSION_EC_TOR_SOCKS5_PORT"] = "  "
        environment["OPALFUSION_EC_TOR_REMOTE_RESOLUTION"] = "\n\t"

        let configuration = try ElectronCashInteropConfiguration.fromEnvironment(environment)

        #expect(configuration.clientConfiguration.torSocks5 == nil)
    }
}
