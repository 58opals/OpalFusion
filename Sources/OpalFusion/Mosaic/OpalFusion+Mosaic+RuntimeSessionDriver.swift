// OpalFusion+Mosaic+RuntimeSessionDriver.swift

extension OpalFusion.Mosaic {
    /// Drives one already-admitted local attempt from validated merged inputs.
    ///
    /// This actor is deliberately transport-independent. It serializes one input stream through
    /// ``RuntimeSession``, emits reducer effects in order, stops permanently at the first terminal
    /// outcome, and turns input-source loss into local cancellation so reservation cleanup remains
    /// reducer-owned. A retry requires a distinct driver and fresh attempt material.
    actor RuntimeSessionDriver {
        private var runtimeSession: RuntimeSession
        private let dependencies: Dependencies
        private var inputTask: Task<Void, Never>?

        private(set) var state: State = .idle

        init(
            runtimeSession: RuntimeSession,
            dependencies: Dependencies
        ) throws {
            guard runtimeSession.configuration.profile.supportsRuntimeSessionDriver else {
                throw InitializationError.unsupportedProfile(
                    runtimeSession.configuration.profile
                )
            }
            if case let .terminal(outcome) = runtimeSession.state {
                throw InitializationError.terminalSession(outcome)
            }
            self.runtimeSession = runtimeSession
            self.dependencies = dependencies
        }

        /// Starts input consumption once. Later calls are idempotent and never restart an attempt.
        func start() {
            guard state == .idle else {
                return
            }

            guard let phase = runtimeSession.state.phase else {
                preconditionFailure("A Mosaic runtime driver requires a nonterminal session")
            }
            state = .running(phase: phase)

            let openInputStream = dependencies.openInputStream
            let closeInputSource = dependencies.closeInputSource
            inputTask = Task { [weak self] in
                do {
                    guard !Task.isCancelled else {
                        return
                    }
                    let inputStream = try await openInputStream()
                    guard !Task.isCancelled else {
                        return
                    }
                    for try await input in inputStream {
                        guard !Task.isCancelled, let self else {
                            return
                        }
                        guard await self.receive(input) else {
                            await closeInputSource()
                            return
                        }
                    }
                    guard !Task.isCancelled, let self else {
                        return
                    }
                    await self.handleInputSourceTermination(.finished)
                    await closeInputSource()
                } catch {
                    guard !Task.isCancelled, let self else {
                        return
                    }
                    await self.handleInputSourceTermination(.failed)
                    await closeInputSource()
                }
            }
        }

        /// Cancels a running attempt once, emits its outputs, and closes the input source.
        func stop() async {
            guard case .running = state else {
                return
            }

            inputTask?.cancel()
            reduceAndEmit(.local(.cancel))
            await dependencies.closeInputSource()
        }

        /// Waits for the source loop and synchronous ordered output delivery to finish.
        func waitForTermination() async {
            let inputTask = inputTask
            await inputTask?.value
        }

        /// Serializes one already-validated local or host result beside the input source.
        ///
        /// A failure-aware executor uses this path to return results from asynchronous host work.
        /// Network adapters continue to use the configured input stream.
        @discardableResult
        func submit(_ input: RuntimeSession.Input) async -> Bool {
            guard case .running = state else {
                return false
            }
            let shouldContinue = receive(input)
            guard !shouldContinue else {
                return true
            }
            inputTask?.cancel()
            await dependencies.closeInputSource()
            return false
        }

        private func receive(_ input: RuntimeSession.Input) -> Bool {
            guard case .running = state else {
                return false
            }

            reduceAndEmit(input)
            if case .running = state {
                return true
            }
            return false
        }

        private func handleInputSourceTermination(
            _ termination: InputSourceTermination
        ) {
            guard case .running = state else {
                return
            }

            reduceAndEmit(.local(.cancel))
            dependencies.outputSink(.inputSourceTerminated(termination))
        }

        private func reduceAndEmit(_ input: RuntimeSession.Input) {
            let effects = runtimeSession.apply(input: input)
            updateState()
            for effect in effects {
                dependencies.outputSink(.runtimeEffect(effect))
            }
        }

        private func updateState() {
            switch runtimeSession.state {
            case let .terminal(outcome):
                state = .terminal(outcome)
            default:
                guard let phase = runtimeSession.state.phase else {
                    preconditionFailure("A nonterminal Mosaic attempt must have a phase")
                }
                state = .running(phase: phase)
            }
        }
    }
}
