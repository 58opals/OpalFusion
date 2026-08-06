// OpalFusion+Session+Mode.swift

public extension OpalFusion.Session {
    /// A configured protocol engine considered by automatic selection.
    enum EngineConfiguration: Sendable, Equatable {
        case cashFusion(OpalFusion.CashFusion.Configuration)
        case mosaic(OpalFusion.Mosaic.Configuration)

        public var engine: OpalFusion.Engine {
            switch self {
            case .cashFusion:
                .cashFusion
            case .mosaic:
                .mosaic
            }
        }
    }

    /// Whether automatic selection may consider a later configured engine.
    enum FallbackPolicy: Sendable, Equatable {
        /// Only the preferred engine may be selected.
        case disabled
        /// A later engine may be selected only before any wallet material is reserved.
        case beforeReservationOnly
    }

    /// Ordered and explicit engine policy for automatic selection.
    struct AutomaticConfiguration: Sendable, Equatable {
        public enum ValidationError: Error, Sendable, Equatable {
            case noCandidates
            case duplicateEngine(OpalFusion.Engine)
        }

        public let candidates: [EngineConfiguration]
        public let fallbackPolicy: FallbackPolicy

        public init(
            candidates: [EngineConfiguration],
            fallbackPolicy: FallbackPolicy
        ) throws {
            guard !candidates.isEmpty else {
                throw ValidationError.noCandidates
            }

            var engines: Set<OpalFusion.Engine> = []
            for candidate in candidates {
                guard engines.insert(candidate.engine).inserted else {
                    throw ValidationError.duplicateEngine(candidate.engine)
                }
            }

            self.candidates = candidates
            self.fallbackPolicy = fallbackPolicy
        }

        public var preferredEngine: OpalFusion.Engine {
            candidates[0].engine
        }
    }

    /// Protocol selection for one future `OpalFusion.Session` instance.
    enum Mode: Sendable, Equatable {
        case automatic(AutomaticConfiguration)
        case cashFusion(OpalFusion.CashFusion.Configuration)
        case mosaic(OpalFusion.Mosaic.Configuration)

        public var configuredEngines: [OpalFusion.Engine] {
            switch self {
            case let .automatic(configuration):
                configuration.candidates.map(\.engine)
            case .cashFusion:
                [.cashFusion]
            case .mosaic:
                [.mosaic]
            }
        }

        public var preferredEngine: OpalFusion.Engine {
            configuredEngines[0]
        }
    }
}
