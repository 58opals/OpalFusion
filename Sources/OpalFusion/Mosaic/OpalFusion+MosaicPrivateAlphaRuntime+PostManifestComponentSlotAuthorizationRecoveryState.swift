// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestComponentSlotAuthorizationRecoveryState.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// App-authenticated sensitive recovery state for one contributor component slot.
    ///
    /// Keep these opaque bytes only inside the application-owned authenticated attempt
    /// record and erase them with the attempt's terminal secret material.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestComponentSlotAuthorizationRecoveryState:
        Sendable,
        Equatable
    {
        @_spi(MosaicPrivateAlpha)
        public let componentRequest: Data
        @_spi(MosaicPrivateAlpha)
        public let bchSignatureRequest: Data

        @_spi(MosaicPrivateAlpha)
        public init(
            componentRequest: Data,
            bchSignatureRequest: Data
        ) {
            self.componentRequest = Data(componentRequest)
            self.bchSignatureRequest = Data(bchSignatureRequest)
        }

        init(
            _ state: OpalFusion.Mosaic.OpalMainnetAlpha
                .ComponentSlotAuthorizationRecoveryState
        ) {
            self.init(
                componentRequest:
                    state.componentRequest.rawRepresentation,
                bchSignatureRequest:
                    state.bchSignatureRequest.rawRepresentation
            )
        }

        func makeInternal() throws -> OpalFusion.Mosaic.OpalMainnetAlpha
            .ComponentSlotAuthorizationRecoveryState {
            try .init(
                componentRequest: .init(
                    rawRepresentation: componentRequest
                ),
                bchSignatureRequest: .init(
                    rawRepresentation: bchSignatureRequest
                )
            )
        }
    }
}
#endif
