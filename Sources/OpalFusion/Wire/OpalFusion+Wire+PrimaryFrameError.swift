// OpalFusion+Wire+PrimaryFrameError.swift

extension OpalFusion.Wire {
    enum PrimaryFrameError: Swift.Error, Equatable {
        case invalidMagic([UInt8])
        case invalidLength(Int)
        case payloadTooLarge(Int)
    }
}
