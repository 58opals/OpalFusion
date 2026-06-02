// LiveRuntimeDriverValidator+ValidationGroup1.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

extension LiveRuntimeDriverValidator {
    @Test("Runtime configuration rejects host names with surrounding whitespace")
    func validateHostNamesWithSurroundingWhitespace() {
        let baseConfiguration = PrimaryRuntimeTestFixtures.configuration

        let paddedCoordinatorConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: " \(baseConfiguration.coordinatorHost) ",
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: baseConfiguration.covertChannel
        )
        #expect(
            OpalFusion.Runtime.validateConfiguration(paddedCoordinatorConfiguration) ==
                "Coordinator host must not include leading or trailing whitespace"
        )

        let paddedTorConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: baseConfiguration.coordinatorHost,
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: baseConfiguration.covertChannel,
            torSocks5: .init(
                host: " 127.0.0.1 ",
                port: 9050
            )
        )
        #expect(
            OpalFusion.Runtime.validateConfiguration(paddedTorConfiguration) ==
                "Tor SOCKS5 host must not include leading or trailing whitespace"
        )
    }

    @Test("Runtime configuration rejects host names with internal whitespace")
    func validateHostNamesWithInternalWhitespace() {
        let baseConfiguration = PrimaryRuntimeTestFixtures.configuration

        let coordinatorConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: "fusion example.org",
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: baseConfiguration.covertChannel
        )
        #expect(
            OpalFusion.Runtime.validateConfiguration(coordinatorConfiguration) ==
                "Coordinator host must not include whitespace"
        )

        let torConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: baseConfiguration.coordinatorHost,
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: baseConfiguration.covertChannel,
            torSocks5: .init(
                host: "127.0.0. 1",
                port: 9050
            )
        )
        #expect(
            OpalFusion.Runtime.validateConfiguration(torConfiguration) ==
                "Tor SOCKS5 host must not include whitespace"
        )
    }

    @Test("Runtime configuration rejects URL-shaped host names")
    func validateURLShapedHostNames() {
        let baseConfiguration = PrimaryRuntimeTestFixtures.configuration

        let coordinatorConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: "https://fusion.example.org",
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: baseConfiguration.covertChannel
        )
        #expect(
            OpalFusion.Runtime.validateConfiguration(coordinatorConfiguration) ==
                "Coordinator host must be a valid host name"
        )

        let torConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: baseConfiguration.coordinatorHost,
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: baseConfiguration.covertChannel,
            torSocks5: .init(
                host: "socks5://127.0.0.1",
                port: 9050
            )
        )
        #expect(
            OpalFusion.Runtime.validateConfiguration(torConfiguration) ==
                "Tor SOCKS5 host must be a valid host name"
        )
    }

    @Test("Runtime configuration rejects malformed DNS host labels")
    func validateMalformedDNSHostLabels() {
        let baseConfiguration = PrimaryRuntimeTestFixtures.configuration

        let coordinatorConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: "-fusion.example.org",
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: baseConfiguration.covertChannel
        )
        #expect(
            OpalFusion.Runtime.validateConfiguration(coordinatorConfiguration) ==
                "Coordinator host must be a valid host name"
        )

        let torConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: baseConfiguration.coordinatorHost,
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: baseConfiguration.covertChannel,
            torSocks5: .init(
                host: "127.0.0.-1",
                port: 9050
            )
        )
        #expect(
            OpalFusion.Runtime.validateConfiguration(torConfiguration) ==
                "Tor SOCKS5 host must be a valid host name"
        )
    }

    @Test("Runtime configuration accepts raw IPv6 host literals")
    func validateRawIPv6HostNames() {
        let baseConfiguration = PrimaryRuntimeTestFixtures.configuration

        let coordinatorConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: "::1",
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: baseConfiguration.covertChannel
        )
        #expect(OpalFusion.Runtime.validateConfiguration(coordinatorConfiguration) == nil)

        let torConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: baseConfiguration.coordinatorHost,
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: baseConfiguration.covertChannel,
            torSocks5: .init(
                host: "::1",
                port: 9050
            )
        )
        #expect(OpalFusion.Runtime.validateConfiguration(torConfiguration) == nil)
    }

    @Test("Runtime configuration rejects unsupported local Tor hostname resolution")
    func validateTorSocks5LocalHostnameResolution() {
        let baseConfiguration = PrimaryRuntimeTestFixtures.configuration
        let torConfiguration = OpalFusion.Client.Configuration(
            coordinatorHost: baseConfiguration.coordinatorHost,
            coordinatorPort: baseConfiguration.coordinatorPort,
            coordinatorRequiresTLS: baseConfiguration.coordinatorRequiresTLS,
            covertChannel: baseConfiguration.covertChannel,
            torSocks5: .init(
                host: "127.0.0.1",
                port: 9_050,
                resolvesCoordinatorHostNameRemotely: false
            )
        )

        #expect(
            OpalFusion.Runtime.validateConfiguration(torConfiguration) ==
                "Tor SOCKS5 remote hostname resolution must be enabled"
        )
    }
}
