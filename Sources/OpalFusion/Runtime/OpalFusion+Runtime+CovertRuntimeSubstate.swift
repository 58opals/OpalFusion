// OpalFusion+Runtime+CovertRuntimeSubstate.swift

extension OpalFusion.Runtime {
    enum CovertRuntimeSubstate: String, Sendable, Equatable {
        case idle
        case preparing
        case prepared
    }
}
