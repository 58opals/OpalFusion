// OpalFusion+MosaicPrivateAlphaRuntime+TerminalReason.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public enum TerminalReason: CaseIterable, Sendable {
        case aborted
        case completed
    }
}

extension OpalFusion.MosaicPrivateAlphaRuntime.TerminalReason {
    init?(recoveryTag: UInt8) {
        switch recoveryTag {
        case 0: self = .aborted
        case 1: self = .completed
        default: return nil
        }
    }

    var recoveryTag: UInt8 {
        switch self {
        case .aborted: 0
        case .completed: 1
        }
    }
}
#endif
