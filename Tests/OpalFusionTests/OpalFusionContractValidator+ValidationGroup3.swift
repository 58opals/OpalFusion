// OpalFusionContractValidator+ValidationGroup3.swift

import Foundation
import OpalDiagnostics
import OpalFusion
import Testing

extension OpalFusionContractValidator {
    @Test("Host transaction finalization APIs name host-owned fusion transaction bytes")
    func validateHostTransactionBoundaryNamesAndPrivacy() async throws {
        let proposal = OpalFusion.Host.TransactionFinalizationProposal(
            unsignedFusionTransactionBytes: [0x01, 0x02],
            sessionHash: [0xAA],
            expectedInputCount: 1,
            expectedOutputCount: 2,
            participantCount: 3
        )
        let finalizedTransaction = OpalFusion.Host.FinalizedTransaction(
            signedFusionTransactionBytes: [0x03, 0x04]
        )
        let assembler: any OpalFusion.Host.TransactionAssembler =
            HostTransactionAssemblerAdapter(finalizedTransaction: finalizedTransaction)

        let hostResult = try await assembler.finalizeFusionTransaction(
            for: .init(rawValue: "round-boundary"),
            proposal: proposal
        )

        #expect(proposal.unsignedFusionTransactionBytes == [0x01, 0x02])
        #expect(proposal.sessionHash == [0xAA])
        #expect(proposal.expectedInputCount == 1)
        #expect(proposal.expectedOutputCount == 2)
        #expect(proposal.participantCount == 3)
        #expect(proposal.isDiagnosticsSafe == false)
        #expect(proposal.diagnosticsPrivacy == OpalDiagnostics.FieldPrivacy.private)
        #expect(finalizedTransaction.signedFusionTransactionBytes == [0x03, 0x04])
        #expect(finalizedTransaction.isDiagnosticsSafe == false)
        #expect(finalizedTransaction.diagnosticsPrivacy == OpalDiagnostics.FieldPrivacy.private)
        #expect(hostResult == finalizedTransaction)
    }

    @Test("Host reservation and blame material are diagnostics-private")
    func validateHostReservationAndBlameMaterialPrivacy() {
        let input = OpalFusion.Host.ParticipantInput(
            outpointTransactionHashBytes: [0xAA, 0xBB],
            outpointIndex: 0,
            amountSatoshis: 1_000,
            lockingScriptBytes: [0x51],
            publicKey: [0x02, 0xCC]
        )
        let output = OpalFusion.Host.ParticipantOutput(
            lockingScriptBytes: [0x76, 0xA9],
            amountSatoshis: 900
        )
        let sessionKeyDecrypter = OpalFusion.Blame.Decrypter.sessionKey(secretBytes: [0x10, 0x11])
        let privateKeyDecrypter = OpalFusion.Blame.Decrypter.privateKey(secretBytes: [0x20, 0x21, 0x22])

        #expect(input.isDiagnosticsSafe == false)
        #expect(input.diagnosticsPrivacy == OpalDiagnostics.FieldPrivacy.private)
        #expect(output.isDiagnosticsSafe == false)
        #expect(output.diagnosticsPrivacy == OpalDiagnostics.FieldPrivacy.private)
        #expect(sessionKeyDecrypter.secretMaterialByteCount == 2)
        #expect(privateKeyDecrypter.secretMaterialByteCount == 3)
        #expect(sessionKeyDecrypter.isDiagnosticsSafe == false)
        #expect(privateKeyDecrypter.isDiagnosticsSafe == false)
        #expect(sessionKeyDecrypter.diagnosticsPrivacy == OpalDiagnostics.FieldPrivacy.private)
        #expect(privateKeyDecrypter.diagnosticsPrivacy == OpalDiagnostics.FieldPrivacy.private)
    }

    @Test("Client session snapshot and observer sources stay display-safe")
    func validateSessionSnapshotAndObserverSourcesStayDisplaySafe() throws {
        let displaySurfaceSource = try [
            "Sources/OpalFusion/Client/OpalFusion+Client+Session+Snapshot.swift",
            "Sources/OpalFusion/Client/OpalFusion+Client+Session+Snapshot+CoordinatorStatus.swift",
            "Sources/OpalFusion/Client/OpalFusion+Client+Session+Snapshot+CoordinatorStatus+TierQueue.swift",
            "Sources/OpalFusion/Client/OpalFusion+Client+StateObserver.swift"
        ]
        .map { try Self.sourceWithoutComments(relativePath: $0) }
        .joined(separator: "\n")

        for forbiddenSnippet in [
            "[UInt8]",
            "TransactionBytes",
            "FusionTransaction",
            "lockingScript",
            "address",
            "privateKey",
            "sessionKey",
            "SwiftData"
        ] {
            #expect(displaySurfaceSource.contains(forbiddenSnippet) == false)
        }
    }

    @Test("Fusion diagnostics fields do not define raw wallet payload fields")
    func validateDiagnosticsFieldsAvoidWalletPayloadNames() throws {
        let diagnosticsSource = try Self.sourceWithoutComments(
            relativePath: "Sources/OpalFusion/Observability/Diagnostics/OpalDiagnostics+Field+OpalFusion.swift"
        )
        let lowercaseSource = diagnosticsSource.lowercased()

        for forbiddenFieldName in [
            "locking_script",
            "script_hex",
            "address",
            "private_key",
            "session_key",
            "raw_tx",
            "transaction_hex",
            "outpoint",
            "public_key_bytes"
        ] {
            #expect(lowercaseSource.contains(forbiddenFieldName) == false)
        }
    }

    @Test("Client session source excludes wallet storage and signing authority")
    func validateClientSessionSourcesExcludeWalletAuthority() throws {
        let sessionSource = try Self.sourceWithoutComments(
            relativePath: "Sources/OpalFusion/Client/OpalFusion+Client+Session.swift"
        )

        #expect(sessionSource.contains("SwiftData") == false)
        #expect(sessionSource.contains("broadcast") == false)
        #expect(sessionSource.contains("privateKey") == false)
        #expect(sessionSource.contains("sessionKey") == false)
    }
}

private extension OpalFusionContractValidator {
    static func sourceWithoutComments(relativePath: String) throws -> String {
        let source = try String(contentsOf: packageRoot.appending(path: relativePath), encoding: .utf8)
        return source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                line.trimmingCharacters(in: .whitespaces).hasPrefix("//") == false
            }
            .joined(separator: "\n")
    }

    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
