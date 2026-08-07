// OpalFusion+Mosaic+OpalV0+NostrContract.swift

extension OpalFusion.Mosaic.OpalV0 {
    enum EventKind: UInt16, CaseIterable, Sendable {
        case discovery = 26_528
        case control = 21_939
        case anonymous = 20_652
    }

    enum NostrContractError: Error, Sendable, Equatable {
        case invalidEventPublicKeyLength(actual: Int)
        case invalidControlIdentityLength(actual: Int)
        case reusedControlAndEventIdentity
        case invalidDiscoveryTags
        case invalidEncryptedTags
    }

    struct IdentityBinding: Sendable, Equatable {
        let eventPublicKey: [UInt8]
        let controlIdentity: [UInt8]

        init(eventPublicKey: [UInt8], controlIdentity: [UInt8]) throws {
            guard eventPublicKey.count == 32 else {
                throw NostrContractError.invalidEventPublicKeyLength(
                    actual: eventPublicKey.count
                )
            }
            guard controlIdentity.count == 32 else {
                throw NostrContractError.invalidControlIdentityLength(
                    actual: controlIdentity.count
                )
            }
            guard eventPublicKey != controlIdentity else {
                throw NostrContractError.reusedControlAndEventIdentity
            }
            self.eventPublicKey = Array(eventPublicKey)
            self.controlIdentity = Array(controlIdentity)
        }
    }

    static func validateDiscoveryTags(_ tags: [[String]]) throws {
        guard tags.isEmpty else {
            throw NostrContractError.invalidDiscoveryTags
        }
    }

    static func encryptedTags(recipientEventPublicKey: [UInt8]) throws -> [[String]] {
        guard recipientEventPublicKey.count == 32 else {
            throw NostrContractError.invalidEventPublicKeyLength(
                actual: recipientEventPublicKey.count
            )
        }
        let digits = Array("0123456789abcdef".utf8)
        let hexadecimalBytes = recipientEventPublicKey.flatMap { byte in
            [digits[Int(byte >> 4)], digits[Int(byte & 0x0f)]]
        }
        let hexadecimal = String(decoding: hexadecimalBytes, as: UTF8.self)
        return [["p", hexadecimal]]
    }

    static func validateEncryptedTags(
        _ tags: [[String]],
        recipientEventPublicKey: [UInt8]
    ) throws {
        guard tags == (try encryptedTags(recipientEventPublicKey: recipientEventPublicKey)) else {
            throw NostrContractError.invalidEncryptedTags
        }
    }
}
