// ElectronCashInteropTestSupport.swift

import Foundation

enum ElectronCashInteropTestSupport {
    static let liveInteropEnvironmentKey = "OPALFUSION_EC_INTEROP"
    static let transcriptCaptureEnvironmentKey = "OPALFUSION_EC_CAPTURE_TRANSCRIPT"
    static let liveCoordinatorTestIdentifier =
        "OpalFusionTests.ElectronCashInteropValidator/validateRealElectronCashCoordinatorInterop()"

    static var isLiveCoordinatorInteropEnabled: Bool {
        ProcessInfo.processInfo.environment[liveInteropEnvironmentKey] == "1"
    }

    static var isTranscriptCaptureEnabled: Bool {
        ProcessInfo.processInfo.environment[transcriptCaptureEnvironmentKey] == "1"
    }
}
