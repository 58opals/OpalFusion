// BlindSigningCoordinator.swift

@testable import OpalFusion
import Foundation
import OpalCrypto

struct BlindSigningCoordinator {
    let roundPrivateKey: [UInt8]
    let roundPublicKey: [UInt8]
    private var signers: [OpalCrypto.BlindSignature.Signer]

    init(numberOfComponents: Int) throws {
        let roundPrivateKey = [UInt8](repeating: 0x31, count: 32)
        self.roundPrivateKey = roundPrivateKey
        self.roundPublicKey = try Array(
            OpalCrypto.Signature.derivePublicKey(
                fromPrivateKey: Data(roundPrivateKey)
            )
        )
        self.signers = try (0..<numberOfComponents).map { _ in
            try OpalCrypto.BlindSignature.Signer()
        }
    }

    var startRound: OpalFusion.ProtocolModel.StartRound {
        .init(
            roundPublicKey: roundPublicKey,
            blindNoncePoints: signers.map { Array($0.noncePoint) },
            serverTimeUnixSeconds: 1_030
        )
    }

    mutating func responses(
        for playerCommit: OpalFusion.ProtocolModel.PlayerCommit
    ) async throws -> OpalFusion.ProtocolModel.BlindSignatureResponses {
        guard playerCommit.blindSignatureRequests.count == signers.count else {
            throw BlindSigningCoordinatorError.invalidBlindRequestCount
        }

        var responses: [OpalFusion.BlindSignature.Response] = []
        responses.reserveCapacity(signers.count)

        for index in signers.indices {
            let scalar = try await signers[index].sign(
                privateKey: Data(roundPrivateKey),
                requestScalar: Data(playerCommit.blindSignatureRequests[index].scalar)
            )
            responses.append(.init(scalar: Array(scalar)))
        }

        return .init(responses: responses)
    }
}
