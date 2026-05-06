// OpalFusion+Runtime+LiveTransport.swift

import CFNetwork
import Foundation
import Network
import OSLog
import Security

extension OpalFusion.Runtime {
    static func validateConfiguration(
        _ configuration: OpalFusion.Client.Configuration
    ) -> String? {
        let coordinatorHost = configuration.coordinatorHost.trimmingCharacters(in: .whitespacesAndNewlines)

        if coordinatorHost.isEmpty {
            return "Coordinator host must not be empty"
        }

        if coordinatorHost != configuration.coordinatorHost {
            return "Coordinator host must not include leading or trailing whitespace"
        }

        if coordinatorHost.hasWhitespace {
            return "Coordinator host must not include whitespace"
        }

        if isValidHostName(coordinatorHost) == false {
            return "Coordinator host must be a valid host name"
        }

        if configuration.coordinatorPort == 0 {
            return "Coordinator port must be greater than zero"
        }

        let covertEntryPath = configuration.covertChannel.entryPath
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if covertEntryPath.isEmpty || covertEntryPath.hasPrefix("/") == false {
            return "Covert entry path must start with /"
        }

        if covertEntryPath != configuration.covertChannel.entryPath {
            return "Covert entry path must not include leading or trailing whitespace"
        }

        if covertEntryPath.hasWhitespace {
            return "Covert entry path must not include whitespace"
        }

        if configuration.covertChannel.maxPayloadBytes <= 0 {
            return "Covert max payload bytes must be greater than zero"
        }

        if configuration.covertChannel.requestTimeoutMilliseconds == 0 {
            return "Covert request timeout must be greater than zero"
        }

        if configuration.covertChannel.requestTimeoutMilliseconds > UInt64(Int64.max) {
            return "Covert request timeout must fit the supported duration range"
        }

        if let torSocks5 = configuration.torSocks5 {
            let torSocks5Host = torSocks5.host.trimmingCharacters(in: .whitespacesAndNewlines)

            if torSocks5Host.isEmpty {
                return "Tor SOCKS5 host must not be empty"
            }

            if torSocks5Host != torSocks5.host {
                return "Tor SOCKS5 host must not include leading or trailing whitespace"
            }

            if torSocks5Host.hasWhitespace {
                return "Tor SOCKS5 host must not include whitespace"
            }

            if isValidHostName(torSocks5Host) == false {
                return "Tor SOCKS5 host must be a valid host name"
            }

            if torSocks5.port == 0 {
                return "Tor SOCKS5 port must be greater than zero"
            }

            if torSocks5.resolvesCoordinatorHostNameRemotely == false {
                return "Tor SOCKS5 remote hostname resolution must be enabled"
            }
        }

        return nil
    }

    static func isValidHostName(_ host: String) -> Bool {
        switch NWEndpoint.Host(host) {
        case .ipv4, .ipv6:
            return true
        case let .name(name, _):
            return name == host &&
                host.contains("/") == false &&
                host.contains(":") == false &&
                host.contains("[") == false &&
                host.contains("]") == false &&
                host.contains("@") == false &&
                isValidDNSName(name)
        @unknown default:
            return false
        }
    }

    private static func isValidDNSName(_ name: String) -> Bool {
        let normalizedName = name.hasSuffix(".") ? name.dropLast() : Substring(name)
        guard normalizedName.isEmpty == false,
              normalizedName.utf8.count <= 253 else {
            return false
        }

        return normalizedName.split(
            separator: ".",
            omittingEmptySubsequences: false
        ).allSatisfy(isValidDNSLabel)
    }

    private static func isValidDNSLabel(_ label: Substring) -> Bool {
        guard label.isEmpty == false,
              label.utf8.count <= 63,
              let first = label.utf8.first,
              let last = label.utf8.last,
              isASCIIAlphanumeric(first),
              isASCIIAlphanumeric(last) else {
            return false
        }

        return label.utf8.allSatisfy { byte in
            isASCIIAlphanumeric(byte) || byte == UInt8(ascii: "-")
        }
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte) ||
            (UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains(byte) ||
            (UInt8(ascii: "a") ... UInt8(ascii: "z")).contains(byte)
    }

    static func validateStartupConfiguration(
        _ configuration: OpalFusion.Client.Configuration,
        genesisHash: [UInt8]?,
        joinPools: OpalFusion.ProtocolModel.JoinPools
    ) -> String? {
        if let summary = validateConfiguration(configuration) {
            return summary
        }

        if let genesisHash, genesisHash.count != 32 {
            return "Genesis hash must be 32 bytes"
        }

        if joinPools.tiers.isEmpty {
            return "Join pool tiers must not be empty"
        }

        if joinPools.tiers.contains(0) {
            return "Join pool tiers must be greater than zero"
        }

        if Set(joinPools.tiers).count != joinPools.tiers.count {
            return "Join pool tiers must not contain duplicates"
        }

        var poolTagIdentifiers: Set<[UInt8]> = []
        for tag in joinPools.tags {
            if tag.identifier.isEmpty {
                return "Join pool tags must include an identifier"
            }

            if poolTagIdentifiers.insert(tag.identifier).inserted == false {
                return "Join pool tags must not contain duplicate identifiers"
            }

            if tag.limit == 0 {
                return "Join pool tag limits must be greater than zero"
            }
        }

        return nil
    }
}
