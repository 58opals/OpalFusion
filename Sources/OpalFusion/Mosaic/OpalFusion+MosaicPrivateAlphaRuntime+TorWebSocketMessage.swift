// OpalFusion+MosaicPrivateAlphaRuntime+TorWebSocketMessage.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public enum TorWebSocketMessage: Sendable, Equatable {
        case text(Data)
        case binary(Data)
    }
}
#endif
