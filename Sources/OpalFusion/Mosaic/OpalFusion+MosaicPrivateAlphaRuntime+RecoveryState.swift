// OpalFusion+MosaicPrivateAlphaRuntime+RecoveryState.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    struct RecoveryState: Equatable, Sendable {
        static let maximumCanonicalEventByteCount = 200_000
        static let maximumRecordByteCount =
            maximumCanonicalEventByteCount + 16
        static let maximumOpaqueByteCount = 200_512
        static let maximumRecordCount = 59
        static let maximumRelayEndpointCount = 3
        static let maximumRelayEndpointByteCount = 2_048
        static let maximumSnapshotByteCount = 12_800_000

        let binding: Binding
        var revision: UInt64
        let discoveryEpochStartUnixSeconds: UInt64
        var phase: Phase
        var preManifestDocuments: [Data]
        var preManifestAbortCause: PreManifestAbortCauseRecoveryState
        var manifestState: ManifestRecoveryState
        var postManifestJournalState: PostManifestJournalRecoveryState
        var publicationState: PrivateDeploymentPublicationRecoveryState
        var terminalState: TerminalRecoveryState

        func canonicalBytes() throws -> Data {
            Data(try encode())
        }

        func digest() throws -> Data {
            Self.sha256(try canonicalBytes())
        }

        var terminalEvidenceIdentifier: Data? {
            switch terminalState {
            case .active:
                nil
            case let .authorized(_, evidence):
                Self.sha256(evidence)
            }
        }

        static func initial(
            binding: Binding,
            discoveryEpochStartUnixSeconds: UInt64
        ) -> Self {
            .init(
                binding: binding,
                revision: 0,
                discoveryEpochStartUnixSeconds:
                    discoveryEpochStartUnixSeconds,
                phase: .discovery,
                preManifestDocuments: [],
                preManifestAbortCause: .none,
                manifestState: .forming,
                postManifestJournalState: .uninitialized,
                publicationState: .none,
                terminalState: .active
            )
        }

        func replacingRevision() throws -> Self {
            guard revision < UInt64.max else {
                throw Failure.recoveryRevisionOverflow
            }
            var replacement = self
            replacement.revision += 1
            return replacement
        }

        func terminalDisposition() -> TerminalDisposition? {
            switch terminalState {
            case .active:
                return nil
            case let .authorized(reason, evidence):
                return .cleanupAuthorized(
                    reason,
                    evidenceIdentifier: Self.sha256(evidence),
                    recoveryRevision: revision
                )
            }
        }

        static func sha256(_ bytes: Data) -> Data {
            Data(OpalCrypto.Hashing.sha256(bytes))
        }
    }
}
#endif
