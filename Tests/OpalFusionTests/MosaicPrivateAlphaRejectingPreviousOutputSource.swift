// MosaicPrivateAlphaRejectingPreviousOutputSource.swift

@_spi(MosaicPrivateAlpha) @testable import OpalFusion

struct MosaicPrivateAlphaRejectingPreviousOutputSource:
    OpalFusion.Host.MosaicPreviousOutputSource {
    func resolvePreviousOutputs(
        for _: [OpalFusion.Host.MosaicPreviousOutputRequest]
    ) async throws -> [OpalFusion.Host.MosaicPreviousOutput] {
        throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
            .invalidStateTransition
    }
}
