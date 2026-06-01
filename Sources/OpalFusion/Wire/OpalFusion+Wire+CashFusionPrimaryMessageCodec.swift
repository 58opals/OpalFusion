// OpalFusion+Wire+CashFusionPrimaryMessageCodec.swift

extension OpalFusion.Wire {
    enum CashFusionPrimaryMessageCodec {
        static func encode(
            _ message: OpalFusion.ProtocolModel.ClientMessage
        ) throws -> [UInt8] {
            var writer = OpalFusion.Wire.CashFusionProtobufWriter()
            switch message {
            case let .clientHello(clientHello):
                try writer.writeBytesField(
                    try encode(clientHello),
                    fieldNumber: 1
                )
            case let .joinPools(joinPools):
                try writer.writeBytesField(
                    encode(joinPools),
                    fieldNumber: 2
                )
            case let .playerCommit(playerCommit):
                try writer.writeBytesField(
                    encode(playerCommit),
                    fieldNumber: 3
                )
            case let .myProofsList(myProofsList):
                try writer.writeBytesField(
                    encode(myProofsList),
                    fieldNumber: 5
                )
            case let .blames(blames):
                try writer.writeBytesField(
                    encode(blames),
                    fieldNumber: 6
                )
            }
            return writer.serializedBytes
        }

        static func encode(
            _ message: OpalFusion.ProtocolModel.ServerMessage
        ) throws -> [UInt8] {
            var writer = OpalFusion.Wire.CashFusionProtobufWriter()
            switch message {
            case let .serverHello(serverHello):
                try writer.writeBytesField(
                    encode(serverHello),
                    fieldNumber: 1
                )
            case let .tierStatusUpdate(update):
                try writer.writeBytesField(
                    encode(update),
                    fieldNumber: 2
                )
            case let .fusionBegin(fusionBegin):
                try writer.writeBytesField(
                    encode(fusionBegin),
                    fieldNumber: 3
                )
            case let .startRound(startRound):
                try writer.writeBytesField(
                    encode(startRound),
                    fieldNumber: 4
                )
            case let .blindSignatureResponses(responses):
                try writer.writeBytesField(
                    encode(responses),
                    fieldNumber: 5
                )
            case let .allCommitments(allCommitments):
                try writer.writeBytesField(
                    encode(allCommitments),
                    fieldNumber: 6
                )
            case let .shareCovertComponents(components):
                try writer.writeBytesField(
                    encode(components),
                    fieldNumber: 7
                )
            case let .fusionResult(result):
                try writer.writeBytesField(
                    encode(result),
                    fieldNumber: 8
                )
            case let .theirProofsList(proofs):
                try writer.writeBytesField(
                    encode(proofs),
                    fieldNumber: 9
                )
            case .restartRound:
                try writer.writeBytesField(
                    [],
                    fieldNumber: 14
                )
            case let .serverFailure(failure):
                try writer.writeBytesField(
                    encode(failure),
                    fieldNumber: 15
                )
            }
            return writer.serializedBytes
        }

        static func decodeClient(
            _ bytes: [UInt8]
        ) throws -> OpalFusion.ProtocolModel.ClientMessage {
            var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
            var message: OpalFusion.ProtocolModel.ClientMessage?

            while let fieldHeader = try reader.nextFieldHeader() {
                switch fieldHeader.number {
                case 1:
                    try assignOneOfPayload(
                        .clientHello(decodeClientHello(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ClientMessage",
                        fieldNumber: 1
                    )
                case 2:
                    try assignOneOfPayload(
                        .joinPools(try decodeJoinPools(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ClientMessage",
                        fieldNumber: 2
                    )
                case 3:
                    try assignOneOfPayload(
                        .playerCommit(try decodePlayerCommit(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ClientMessage",
                        fieldNumber: 3
                    )
                case 5:
                    try assignOneOfPayload(
                        .myProofsList(try decodeMyProofsList(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ClientMessage",
                        fieldNumber: 5
                    )
                case 6:
                    try assignOneOfPayload(
                        .blames(try decodeBlames(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ClientMessage",
                        fieldNumber: 6
                    )
                default:
                    try reader.skipValue(for: fieldHeader)
                }
            }

            guard let message else {
                throw OpalFusion.Wire.PrimaryMessageCodecError.missingClientMessageCase
            }
            return message
        }

        static func decodeServer(
            _ bytes: [UInt8]
        ) throws -> OpalFusion.ProtocolModel.ServerMessage {
            var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
            var message: OpalFusion.ProtocolModel.ServerMessage?

            while let fieldHeader = try reader.nextFieldHeader() {
                switch fieldHeader.number {
                case 1:
                    try assignOneOfPayload(
                        .serverHello(try decodeServerHello(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 1
                    )
                case 2:
                    try assignOneOfPayload(
                        .tierStatusUpdate(try decodeTierStatusUpdate(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 2
                    )
                case 3:
                    try assignOneOfPayload(
                        .fusionBegin(try decodeFusionBegin(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 3
                    )
                case 4:
                    try assignOneOfPayload(
                        .startRound(try decodeStartRound(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 4
                    )
                case 5:
                    try assignOneOfPayload(
                        .blindSignatureResponses(try decodeBlindSignatureResponses(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 5
                    )
                case 6:
                    try assignOneOfPayload(
                        .allCommitments(try decodeAllCommitments(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 6
                    )
                case 7:
                    try assignOneOfPayload(
                        .shareCovertComponents(try decodeShareCovertComponents(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 7
                    )
                case 8:
                    try assignOneOfPayload(
                        .fusionResult(try decodeFusionResult(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 8
                    )
                case 9:
                    try assignOneOfPayload(
                        .theirProofsList(try decodeTheirProofsList(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 9
                    )
                case 14:
                    try decodeEmptyMessage(try reader.readBytesValue(for: fieldHeader))
                    try assignOneOfPayload(
                        .restartRound(.init()),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 14
                    )
                case 15:
                    try assignOneOfPayload(
                        .serverFailure(try decodeServerFailure(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 15
                    )
                default:
                    try reader.skipValue(for: fieldHeader)
                }
            }

            guard let message else {
                throw OpalFusion.Wire.PrimaryMessageCodecError.missingServerMessageCase
            }
            return message
        }
    }
}

private extension OpalFusion.Wire.CashFusionPrimaryMessageCodec {
    static func encode(
        _ message: OpalFusion.ProtocolModel.ClientHello
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBytesField(
            message.versionBytes,
            fieldNumber: 1
        )
        if let genesisHash = message.genesisHash {
            try writer.writeBytesField(
                genesisHash,
                fieldNumber: 2
            )
        }
        return writer.serializedBytes
    }

    static func decodeClientHello(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.ClientHello {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var versionBytes: [UInt8] = []
        var genesisHash: [UInt8]?

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                versionBytes = try reader.readBytesValue(for: fieldHeader)
            case 2:
                genesisHash = try reader.readBytesValue(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            versionBytes: versionBytes,
            genesisHash: genesisHash
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.JoinPools
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for tier in message.tiers {
            try writer.writeUInt64Field(
                tier,
                fieldNumber: 1
            )
        }
        for tag in message.tags {
            try writer.writeBytesField(
                encode(tag),
                fieldNumber: 2
            )
        }
        return writer.serializedBytes
    }

    static func decodeJoinPools(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.JoinPools {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var tiers: [UInt64] = []
        var tags: [OpalFusion.ProtocolModel.PoolTag] = []

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                tiers.append(contentsOf: try reader.readRepeatedUInt64Values(for: fieldHeader))
            case 2:
                tags.append(try decodePoolTag(try reader.readBytesValue(for: fieldHeader)))
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            tiers: tiers,
            tags: tags
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.PoolTag
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBytesField(
            message.identifier,
            fieldNumber: 1
        )
        try writer.writeUInt32Field(
            message.limit,
            fieldNumber: 2
        )
        if let noIp = message.noIp {
            try writer.writeBoolField(
                noIp,
                fieldNumber: 3
            )
        }
        return writer.serializedBytes
    }

    static func decodePoolTag(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.PoolTag {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var identifier: [UInt8] = []
        var limit: UInt32 = 0
        var noIp: Bool?

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                identifier = try reader.readBytesValue(for: fieldHeader)
            case 2:
                limit = try reader.readUInt32Value(for: fieldHeader)
            case 3:
                noIp = try reader.readBoolValue(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            identifier: identifier,
            limit: limit,
            noIp: noIp
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.PlayerCommit
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for initialCommitment in message.initialCommitments {
            try writer.writeBytesField(
                OpalFusion.Wire.CashFusionInitialCommitmentCodec.encode(
                    initialCommitment
                ),
                fieldNumber: 1
            )
        }
        try writer.writeUInt64Field(
            message.excessFeeSatoshis,
            fieldNumber: 2
        )
        try writer.writeBytesField(
            message.pedersenTotalNonce,
            fieldNumber: 3
        )
        try writer.writeBytesField(
            message.randomNumberCommitment,
            fieldNumber: 4
        )
        for request in message.blindSignatureRequests {
            try writer.writeBytesField(
                request.scalar,
                fieldNumber: 5
            )
        }
        return writer.serializedBytes
    }

    static func decodePlayerCommit(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.PlayerCommit {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var initialCommitments: [OpalFusion.Commitment.InitialCommitment] = []
        var excessFeeSatoshis: UInt64 = 0
        var pedersenTotalNonce: [UInt8] = []
        var randomNumberCommitment: [UInt8] = []
        var blindSignatureRequests: [OpalFusion.BlindSignature.Request] = []

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                initialCommitments.append(
                    try OpalFusion.Wire.CashFusionInitialCommitmentCodec.decode(
                        try reader.readBytesValue(for: fieldHeader)
                    )
                )
            case 2:
                excessFeeSatoshis = try reader.readUInt64Value(for: fieldHeader)
            case 3:
                pedersenTotalNonce = try reader.readBytesValue(for: fieldHeader)
            case 4:
                randomNumberCommitment = try reader.readBytesValue(for: fieldHeader)
            case 5:
                blindSignatureRequests.append(
                    .init(scalar: try reader.readBytesValue(for: fieldHeader))
                )
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            initialCommitments: initialCommitments,
            excessFeeSatoshis: excessFeeSatoshis,
            pedersenTotalNonce: pedersenTotalNonce,
            randomNumberCommitment: randomNumberCommitment,
            blindSignatureRequests: blindSignatureRequests
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.MyProofsList
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for encryptedProof in message.encryptedProofs {
            try writer.writeBytesField(
                encryptedProof,
                fieldNumber: 1
            )
        }
        try writer.writeBytesField(
            message.randomNumber,
            fieldNumber: 2
        )
        return writer.serializedBytes
    }

    static func decodeMyProofsList(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.MyProofsList {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var encryptedProofs: [[UInt8]] = []
        var randomNumber: [UInt8] = []

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                encryptedProofs.append(try reader.readBytesValue(for: fieldHeader))
            case 2:
                randomNumber = try reader.readBytesValue(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            encryptedProofs: encryptedProofs,
            randomNumber: randomNumber
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.Blames
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for blame in message.blames {
            try writer.writeBytesField(
                encode(blame),
                fieldNumber: 1
            )
        }
        return writer.serializedBytes
    }

    static func decodeBlames(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.Blames {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var blames: [OpalFusion.Blame.BlameProof] = []

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                blames.append(try decodeBlameProof(try reader.readBytesValue(for: fieldHeader)))
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(blames: blames)
    }

    static func encode(
        _ message: OpalFusion.Blame.BlameProof
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeUInt32Field(
            message.proofIndex,
            fieldNumber: 1
        )
        switch message.decrypter {
        case let .sessionKey(sessionKey):
            try writer.writeBytesField(
                sessionKey,
                fieldNumber: 2
            )
        case let .privateKey(privateKey):
            try writer.writeBytesField(
                privateKey,
                fieldNumber: 3
            )
        }
        if let requiresLookup = message.requiresBlockchainLookup {
            try writer.writeBoolField(
                requiresLookup,
                fieldNumber: 4
            )
        }
        if let reason = message.reason {
            try writer.writeStringField(
                reason,
                fieldNumber: 5
            )
        }
        return writer.serializedBytes
    }

    static func decodeBlameProof(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.Blame.BlameProof {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var proofIndex: UInt32 = 0
        var decrypter: OpalFusion.Blame.Decrypter?
        var requiresBlockchainLookup: Bool?
        var reason: String?

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                proofIndex = try reader.readUInt32Value(for: fieldHeader)
            case 2:
                try assignOneOfPayload(
                    .sessionKey(try reader.readBytesValue(for: fieldHeader)),
                    to: &decrypter,
                    messageName: "BlameProof",
                    fieldNumber: 2
                )
            case 3:
                try assignOneOfPayload(
                    .privateKey(try reader.readBytesValue(for: fieldHeader)),
                    to: &decrypter,
                    messageName: "BlameProof",
                    fieldNumber: 3
                )
            case 4:
                requiresBlockchainLookup = try reader.readBoolValue(for: fieldHeader)
            case 5:
                reason = try readStringValue(
                    for: fieldHeader,
                    from: &reader,
                    fieldName: "BlameProof.blameReason"
                )
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        guard let decrypter else {
            throw OpalFusion.Wire.PrimaryMessageCodecError.missingBlameDecrypter
        }

        return .init(
            proofIndex: proofIndex,
            decrypter: decrypter,
            requiresBlockchainLookup: requiresBlockchainLookup,
            reason: reason
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.ServerHello
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for tier in message.tiers {
            try writer.writeUInt64Field(
                tier,
                fieldNumber: 1
            )
        }
        try writer.writeUInt32Field(
            message.numberOfComponents,
            fieldNumber: 2
        )
        try writer.writeUInt64Field(
            message.componentFeeRateSatoshisPerKb,
            fieldNumber: 4
        )
        try writer.writeUInt64Field(
            message.minimumExcessFeeSatoshis,
            fieldNumber: 5
        )
        try writer.writeUInt64Field(
            message.maximumExcessFeeSatoshis,
            fieldNumber: 6
        )
        if let donationAddress = message.donationAddress {
            try writer.writeStringField(
                donationAddress,
                fieldNumber: 15
            )
        }
        return writer.serializedBytes
    }

    static func decodeServerHello(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.ServerHello {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var tiers: [UInt64] = []
        var numberOfComponents: UInt32 = 0
        var componentFeeRateSatoshisPerKb: UInt64 = 0
        var minimumExcessFeeSatoshis: UInt64 = 0
        var maximumExcessFeeSatoshis: UInt64 = 0
        var donationAddress: String?

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                tiers.append(contentsOf: try reader.readRepeatedUInt64Values(for: fieldHeader))
            case 2:
                numberOfComponents = try reader.readUInt32Value(for: fieldHeader)
            case 4:
                componentFeeRateSatoshisPerKb = try reader.readUInt64Value(for: fieldHeader)
            case 5:
                minimumExcessFeeSatoshis = try reader.readUInt64Value(for: fieldHeader)
            case 6:
                maximumExcessFeeSatoshis = try reader.readUInt64Value(for: fieldHeader)
            case 15:
                donationAddress = try readStringValue(
                    for: fieldHeader,
                    from: &reader,
                    fieldName: "ServerHello.donationAddress"
                )
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            tiers: tiers,
            numberOfComponents: numberOfComponents,
            componentFeeRateSatoshisPerKb: componentFeeRateSatoshisPerKb,
            minimumExcessFeeSatoshis: minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: maximumExcessFeeSatoshis,
            donationAddress: donationAddress
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.TierStatusUpdate
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for (tier, status) in message.statusesByTier.sorted(by: { $0.key < $1.key }) {
            try writer.writeBytesField(
                encodeTierStatusMapEntry(
                    tier: tier,
                    status: status
                ),
                fieldNumber: 1
            )
        }
        return writer.serializedBytes
    }

    static func decodeTierStatusUpdate(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.TierStatusUpdate {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var statusesByTier: [UInt64: OpalFusion.ProtocolModel.TierStatus] = [:]

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                let entry = try decodeTierStatusMapEntry(
                    try reader.readBytesValue(for: fieldHeader)
                )
                statusesByTier[entry.tier] = entry.status
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(statusesByTier: statusesByTier)
    }

    static func encodeTierStatusMapEntry(
        tier: UInt64,
        status: OpalFusion.ProtocolModel.TierStatus
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeUInt64Field(
            tier,
            fieldNumber: 1
        )
        try writer.writeBytesField(
            encode(status),
            fieldNumber: 2
        )
        return writer.serializedBytes
    }

    static func decodeTierStatusMapEntry(
        _ bytes: [UInt8]
    ) throws -> (tier: UInt64, status: OpalFusion.ProtocolModel.TierStatus) {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var tier: UInt64 = 0
        var status = OpalFusion.ProtocolModel.TierStatus(
            playerCount: nil,
            minimumPlayerCount: nil,
            maximumPlayerCount: nil,
            timeRemainingSeconds: nil
        )

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                tier = try reader.readUInt64Value(for: fieldHeader)
            case 2:
                status = try decodeTierStatus(try reader.readBytesValue(for: fieldHeader))
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return (tier, status)
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.TierStatus
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        if let playerCount = message.playerCount {
            try writer.writeUInt32Field(
                playerCount,
                fieldNumber: 1
            )
        }
        if let minimumPlayerCount = message.minimumPlayerCount {
            try writer.writeUInt32Field(
                minimumPlayerCount,
                fieldNumber: 2
            )
        }
        if let maximumPlayerCount = message.maximumPlayerCount {
            try writer.writeUInt32Field(
                maximumPlayerCount,
                fieldNumber: 3
            )
        }
        if let timeRemainingSeconds = message.timeRemainingSeconds {
            try writer.writeUInt32Field(
                timeRemainingSeconds,
                fieldNumber: 4
            )
        }
        return writer.serializedBytes
    }

    static func decodeTierStatus(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.TierStatus {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var playerCount: UInt32?
        var minimumPlayerCount: UInt32?
        var maximumPlayerCount: UInt32?
        var timeRemainingSeconds: UInt32?

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                playerCount = try reader.readUInt32Value(for: fieldHeader)
            case 2:
                minimumPlayerCount = try reader.readUInt32Value(for: fieldHeader)
            case 3:
                maximumPlayerCount = try reader.readUInt32Value(for: fieldHeader)
            case 4:
                timeRemainingSeconds = try reader.readUInt32Value(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            playerCount: playerCount,
            minimumPlayerCount: minimumPlayerCount,
            maximumPlayerCount: maximumPlayerCount,
            timeRemainingSeconds: timeRemainingSeconds
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.FusionBegin
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeUInt64Field(
            message.tier,
            fieldNumber: 1
        )
        try writer.writeBytesField(
            Array(message.covertDomain.utf8),
            fieldNumber: 2
        )
        try writer.writeUInt32Field(
            message.covertPort,
            fieldNumber: 3
        )
        if let covertSsl = message.covertSsl {
            try writer.writeBoolField(
                covertSsl,
                fieldNumber: 4
            )
        }
        try writer.writeFixed64Field(
            message.serverTimeUnixSeconds,
            fieldNumber: 5
        )
        return writer.serializedBytes
    }

    static func decodeFusionBegin(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.FusionBegin {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var tier: UInt64 = 0
        var covertDomain = ""
        var covertPort: UInt32 = 0
        var covertSsl: Bool?
        var serverTimeUnixSeconds: UInt64 = 0

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                tier = try reader.readUInt64Value(for: fieldHeader)
            case 2:
                covertDomain = try readStringValue(
                    for: fieldHeader,
                    from: &reader,
                    fieldName: "FusionBegin.covertDomain"
                )
            case 3:
                covertPort = try reader.readUInt32Value(for: fieldHeader)
            case 4:
                covertSsl = try reader.readBoolValue(for: fieldHeader)
            case 5:
                serverTimeUnixSeconds = try reader.readFixed64Value(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            tier: tier,
            covertDomain: covertDomain,
            covertPort: covertPort,
            covertSsl: covertSsl,
            serverTimeUnixSeconds: serverTimeUnixSeconds
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.StartRound
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBytesField(
            message.roundPublicKey,
            fieldNumber: 1
        )
        for blindNoncePoint in message.blindNoncePoints {
            try writer.writeBytesField(
                blindNoncePoint,
                fieldNumber: 2
            )
        }
        try writer.writeFixed64Field(
            message.serverTimeUnixSeconds,
            fieldNumber: 5
        )
        return writer.serializedBytes
    }

    static func decodeStartRound(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.StartRound {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var roundPublicKey: [UInt8] = []
        var blindNoncePoints: [[UInt8]] = []
        var serverTimeUnixSeconds: UInt64 = 0

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                roundPublicKey = try reader.readBytesValue(for: fieldHeader)
            case 2:
                blindNoncePoints.append(try reader.readBytesValue(for: fieldHeader))
            case 5:
                serverTimeUnixSeconds = try reader.readFixed64Value(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            roundPublicKey: roundPublicKey,
            blindNoncePoints: blindNoncePoints,
            serverTimeUnixSeconds: serverTimeUnixSeconds
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.BlindSignatureResponses
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for response in message.responses {
            try writer.writeBytesField(
                response.scalar,
                fieldNumber: 1
            )
        }
        return writer.serializedBytes
    }

    static func decodeBlindSignatureResponses(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.BlindSignatureResponses {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var responses: [OpalFusion.BlindSignature.Response] = []

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                responses.append(.init(scalar: try reader.readBytesValue(for: fieldHeader)))
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(responses: responses)
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.AllCommitments
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for initialCommitment in message.initialCommitments {
            try writer.writeBytesField(
                OpalFusion.Wire.CashFusionInitialCommitmentCodec.encode(
                    initialCommitment
                ),
                fieldNumber: 1
            )
        }
        return writer.serializedBytes
    }

    static func decodeAllCommitments(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.AllCommitments {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var initialCommitments: [OpalFusion.Commitment.InitialCommitment] = []

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                initialCommitments.append(
                    try OpalFusion.Wire.CashFusionInitialCommitmentCodec.decode(
                        try reader.readBytesValue(for: fieldHeader)
                    )
                )
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(initialCommitments: initialCommitments)
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.ShareCovertComponents
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for component in message.serializedComponents {
            try writer.writeBytesField(
                component,
                fieldNumber: 4
            )
        }
        if let skipSignatures = message.skipSignatures {
            try writer.writeBoolField(
                skipSignatures,
                fieldNumber: 5
            )
        }
        if let sessionHash = message.sessionHash {
            try writer.writeBytesField(
                sessionHash,
                fieldNumber: 6
            )
        }
        return writer.serializedBytes
    }

    static func decodeShareCovertComponents(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.ShareCovertComponents {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var serializedComponents: [[UInt8]] = []
        var skipSignatures: Bool?
        var sessionHash: [UInt8]?

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 4:
                serializedComponents.append(try reader.readBytesValue(for: fieldHeader))
            case 5:
                skipSignatures = try reader.readBoolValue(for: fieldHeader)
            case 6:
                sessionHash = try reader.readBytesValue(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            serializedComponents: serializedComponents,
            skipSignatures: skipSignatures,
            sessionHash: sessionHash
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.FusionResult
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBoolField(
            message.isSuccess,
            fieldNumber: 1
        )
        for transactionSignature in message.transactionSignatures {
            try writer.writeBytesField(
                transactionSignature,
                fieldNumber: 2
            )
        }
        for badComponentIndex in message.badComponentIndices {
            try writer.writeUInt32Field(
                badComponentIndex,
                fieldNumber: 3
            )
        }
        return writer.serializedBytes
    }

    static func decodeFusionResult(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.FusionResult {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var isSuccess = false
        var transactionSignatures: [[UInt8]] = []
        var badComponentIndices: [UInt32] = []

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                isSuccess = try reader.readBoolValue(for: fieldHeader)
            case 2:
                transactionSignatures.append(try reader.readBytesValue(for: fieldHeader))
            case 3:
                badComponentIndices.append(
                    contentsOf: try reader.readRepeatedUInt32Values(for: fieldHeader)
                )
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            isSuccess: isSuccess,
            transactionSignatures: transactionSignatures,
            badComponentIndices: badComponentIndices
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.TheirProofsList
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for proof in message.proofs {
            try writer.writeBytesField(
                encode(proof),
                fieldNumber: 1
            )
        }
        return writer.serializedBytes
    }

    static func decodeTheirProofsList(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.TheirProofsList {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var proofs: [OpalFusion.Blame.RelayedProof] = []

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                proofs.append(try decodeRelayedProof(try reader.readBytesValue(for: fieldHeader)))
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(proofs: proofs)
    }

    static func encode(
        _ message: OpalFusion.Blame.RelayedProof
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBytesField(
            message.encryptedProof,
            fieldNumber: 1
        )
        try writer.writeUInt32Field(
            message.sourceCommitmentIndex,
            fieldNumber: 2
        )
        try writer.writeUInt32Field(
            message.destinationKeyIndex,
            fieldNumber: 3
        )
        return writer.serializedBytes
    }

    static func decodeRelayedProof(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.Blame.RelayedProof {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var encryptedProof: [UInt8] = []
        var sourceCommitmentIndex: UInt32 = 0
        var destinationKeyIndex: UInt32 = 0

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                encryptedProof = try reader.readBytesValue(for: fieldHeader)
            case 2:
                sourceCommitmentIndex = try reader.readUInt32Value(for: fieldHeader)
            case 3:
                destinationKeyIndex = try reader.readUInt32Value(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            encryptedProof: encryptedProof,
            sourceCommitmentIndex: sourceCommitmentIndex,
            destinationKeyIndex: destinationKeyIndex
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.ServerFailure
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        if let text = message.message {
            try writer.writeStringField(
                text,
                fieldNumber: 1
            )
        }
        return writer.serializedBytes
    }

    static func decodeServerFailure(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.ServerFailure {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var message: String?

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                message = try readStringValue(
                    for: fieldHeader,
                    from: &reader,
                    fieldName: "Error.message"
                )
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(message: message)
    }

    static func decodeEmptyMessage(_ bytes: [UInt8]) throws {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        while let fieldHeader = try reader.nextFieldHeader() {
            try reader.skipValue(for: fieldHeader)
        }
    }

    static func assignOneOfPayload<Value>(
        _ nextPayload: Value,
        to payload: inout Value?,
        messageName: String,
        fieldNumber: Int
    ) throws {
        guard payload == nil else {
            throw OpalFusion.Wire.CashFusionProtobufCodingError.conflictingOneOfField(
                messageName: messageName,
                fieldNumber: fieldNumber
            )
        }
        payload = nextPayload
    }

    static func readStringValue(
        for fieldHeader: OpalFusion.Wire.CashFusionProtobufFieldHeader,
        from reader: inout OpalFusion.Wire.CashFusionProtobufReader,
        fieldName: String
    ) throws -> String {
        do {
            return try reader.readStringValue(for: fieldHeader)
        } catch OpalFusion.Wire.CashFusionProtobufCodingError.invalidUTF8String {
            throw OpalFusion.Wire.PrimaryMessageCodecError.invalidUTF8Field(
                fieldName
            )
        }
    }
}
