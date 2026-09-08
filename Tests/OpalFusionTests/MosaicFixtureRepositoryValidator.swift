// MosaicFixtureRepositoryValidator.swift

import Testing

@Suite("Mosaic immutable fixture repository")
struct MosaicFixtureRepositoryValidator {
    @Test("Caller cancellation preserves shared construction and later consumers")
    func preserveConstructionAfterCallerCancellation() async throws {
        let repository = MosaicFixtureRepository<Int>()
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let cancelled = Task {
            try await repository.load {
                started.continuation.yield(())
                for await _ in release.stream { break }
                return 42
            }
        }
        for await _ in started.stream { break }
        cancelled.cancel()
        let independent = Task {
            try await repository.load { 99 }
        }
        release.continuation.yield(())
        release.continuation.finish()
        started.continuation.finish()

        #expect(try await cancelled.value == 42)
        #expect(try await independent.value == 42)
        #expect(cancelled.isCancelled)
        #expect(!independent.isCancelled)
        #expect(try await repository.load { 100 } == 42)
    }

    @Test("A failed construction remains visible without retry or fallback")
    func preserveConstructionFailure() async {
        let repository = MosaicFixtureRepository<Int>()
        await #expect(throws: MosaicFixtureConstructionError.expected) {
            try await repository.load {
                throw MosaicFixtureConstructionError.expected
            }
        }
        await #expect(throws: MosaicFixtureConstructionError.expected) {
            try await repository.load { 42 }
        }
    }
}
