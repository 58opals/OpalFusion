// ClientSessionValidatorSupport.swift

@testable import OpalFusion

enum ClientSessionValidatorSupport {
    static func isUnsupportedReservationTerminalSnapshot(
        _ snapshot: OpalFusion.Client.Session.Snapshot
    ) -> Bool {
        snapshot.lastError == .notImplemented &&
            snapshot.state.round?.completionStatus == .hostRejected &&
            snapshot.state.isConnected == false
    }

    static func makeTrustedTLSPrimaryTransport(
        port: UInt16
    ) async throws -> OpalFusion.Runtime.LivePrimaryTransport {
        OpalFusion.Runtime.LivePrimaryTransport(
            host: LoopbackPrimaryTLSTestFixture.host,
            port: port,
            requiresTLS: true,
            tlsTrustAnchorCertificateDERs: try await LoopbackPrimaryTLSTestFixture
                .trustAnchorCertificateDERs()
        )
    }

    static func makeRoundAwareScriptedWorkflow() -> OpalFusion.Execution.WorkflowContext {
        .init(
            buildPlayerCommit: { _ in
                PrimaryRuntimeTestFixtures.playerCommit
            },
            buildCovertComponentMessages: { round in
                let roundPublicKey = round.startRound?.roundPublicKey ?? []
                return [
                    .component(
                        .init(
                            roundPublicKey: roundPublicKey,
                            signature: [0x30],
                            serializedComponent: [0x31]
                        )
                    )
                ]
            },
            buildTransactionFinalizationProposal: { _ in
                PrimaryRuntimeTestFixtures.transactionProposal
            },
            buildCovertSignatureMessages: { round in
                let roundPublicKey = round.startRound?.roundPublicKey ?? []
                return [
                    .transactionSignature(
                        .init(
                            roundPublicKey: roundPublicKey,
                            inputIndex: 0,
                            transactionSignature: [0x61]
                        )
                    )
                ]
            },
            buildMyProofsList: { _ in
                PrimaryRuntimeTestFixtures.myProofsList
            },
            buildBlames: { _ in
                PrimaryRuntimeTestFixtures.blames
            }
        )
    }
}
