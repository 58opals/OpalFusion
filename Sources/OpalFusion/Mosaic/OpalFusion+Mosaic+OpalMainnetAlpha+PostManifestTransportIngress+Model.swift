// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestTransportIngress+Model.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha.PostManifestTransportIngress {
    typealias Driver = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestRuntimeDriver
    typealias Transport = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestNIP59Transport

    struct Dependencies: Sendable {
        let currentUnixSeconds: @Sendable () -> UInt64
        let beforeDriverStart: @Sendable () async -> Void

        init(
            currentUnixSeconds: @escaping @Sendable () -> UInt64,
            beforeDriverStart: @escaping @Sendable () async -> Void = {}
        ) {
            self.currentUnixSeconds = currentUnixSeconds
            self.beforeDriverStart = beforeDriverStart
        }
    }

    enum InitializationError: Error, Sendable, Equatable {
        case runtimeDriver(Driver.InitializationError)
    }

    enum State: Sendable, Equatable {
        case idle
        case starting
        case running
        case stopping
        case terminal(Driver.State)
    }

    enum Rejection: Error, Sendable, Equatable {
        case notRunning
        case transport(Transport.Failure)
        case runtimeRejected
    }

    enum Decision: Sendable, Equatable {
        case accepted
        case rejected(Rejection)
    }
}
