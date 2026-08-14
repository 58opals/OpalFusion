// OpalFusion+Mosaic+OpalMainnetAlpha+PrivateRelayEndpoint.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Canonical private-deployment relay URL with no embedded network credentials.
    struct PrivateRelayEndpoint: Sendable, Hashable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidScheme
            case invalidAuthority
            case unsupportedPort
            case userInformationNotPermitted
            case nonRootPathNotPermitted
            case queryNotPermitted
            case fragmentNotPermitted
            case nonASCIIHost
            case invalidDNSHost
            case IPAddressNotPermitted
        }

        let normalizedURL: String

        init(normalizing suppliedURL: String) throws(ValidationError) {
            let suppliedBytes = Array(suppliedURL.utf8)
            guard suppliedBytes.allSatisfy({ $0 < 0x80 }) else {
                throw .nonASCIIHost
            }
            let lowercaseBytes = suppliedBytes.map { byte in
                (0x41 ... 0x5A).contains(byte) ? byte + 0x20 : byte
            }
            let lowercaseURL = String(decoding: lowercaseBytes, as: UTF8.self)
            guard lowercaseURL.hasPrefix("wss://") else {
                throw .invalidScheme
            }

            let remainder = String(lowercaseURL.dropFirst(6))
            guard !remainder.contains("@") else {
                throw .userInformationNotPermitted
            }
            guard !remainder.contains("?") else { throw .queryNotPermitted }
            guard !remainder.contains("#") else { throw .fragmentNotPermitted }

            let authority: String
            if let slashIndex = remainder.firstIndex(of: "/") {
                guard remainder[slashIndex...] == "/" else {
                    throw .nonRootPathNotPermitted
                }
                authority = String(remainder[..<slashIndex])
            } else {
                authority = remainder
            }
            guard !authority.isEmpty else { throw .invalidAuthority }
            guard !authority.contains("[") && !authority.contains("]") else {
                throw .IPAddressNotPermitted
            }

            let host: String
            if let colonIndex = authority.lastIndex(of: ":") {
                guard authority[..<colonIndex].contains(":") == false else {
                    throw .IPAddressNotPermitted
                }
                guard authority[authority.index(after: colonIndex)...] == "443" else {
                    throw .unsupportedPort
                }
                host = String(authority[..<colonIndex])
            } else {
                host = authority
            }
            try Self.validateDNSHost(host)
            normalizedURL = "wss://\(host)/"
        }

        private static func validateDNSHost(
            _ host: String
        ) throws(ValidationError) {
            guard !host.isEmpty, host.utf8.count <= 253,
                  !host.hasPrefix("."), !host.hasSuffix("."),
                  !host.contains("%") else {
                throw .invalidDNSHost
            }
            let labels = host.split(separator: ".", omittingEmptySubsequences: false)
            guard labels.count >= 2,
                  labels.last?.utf8.contains(where: {
                      (0x61 ... 0x7A).contains($0)
                  }) == true else {
                throw .invalidDNSHost
            }
            for label in labels {
                guard !label.isEmpty, label.utf8.count <= 63,
                      label.first != "-", label.last != "-",
                      label.utf8.allSatisfy({ byte in
                          (0x61 ... 0x7A).contains(byte)
                              || (0x30 ... 0x39).contains(byte)
                              || byte == 0x2D
                      }) else {
                    throw .invalidDNSHost
                }
            }
            guard !host.utf8.allSatisfy({ byte in
                (0x30 ... 0x39).contains(byte) || byte == 0x2E
            }) else {
                throw .IPAddressNotPermitted
            }
        }
    }
}
