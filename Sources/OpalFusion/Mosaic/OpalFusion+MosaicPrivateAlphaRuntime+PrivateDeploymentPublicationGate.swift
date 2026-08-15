// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentPublicationGate.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    actor PrivateDeploymentPublicationGate {
        private var isClaimed = false

        func claim() -> Bool {
            guard !isClaimed else { return false }
            isClaimed = true
            return true
        }
    }
}
#endif
