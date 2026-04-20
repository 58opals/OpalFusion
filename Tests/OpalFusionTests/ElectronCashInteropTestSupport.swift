// ElectronCashInteropTestSupport.swift

enum ElectronCashInteropTestSupport {
    static func requiredString(
        _ name: String,
        in environment: [String: String]
    ) throws -> String {
        guard let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            throw ElectronCashInteropEnvironmentError.missing(name)
        }
        return value
    }

    static func requiredUInt16(
        _ name: String,
        in environment: [String: String]
    ) throws -> UInt16 {
        try parseUInt16(
            requiredString(name, in: environment),
            variableName: name
        )
    }

    static func requiredUInt32(
        _ name: String,
        in environment: [String: String]
    ) throws -> UInt32 {
        try parseUInt32(
            requiredString(name, in: environment),
            variableName: name
        )
    }

    static func requiredUInt64(
        _ name: String,
        in environment: [String: String]
    ) throws -> UInt64 {
        try parseUInt64(
            requiredString(name, in: environment),
            variableName: name
        )
    }

    static func requiredHexBytes(
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

    static func parseUInt16(
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

    static func parseUInt32(
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

    static func parseUInt64(
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

    static func parseOptionalBool(
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

    static func parseHexBytes(
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
}
