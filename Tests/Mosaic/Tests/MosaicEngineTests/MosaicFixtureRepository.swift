// MosaicFixtureRepository.swift

actor MosaicFixtureRepository<Value: Sendable> {
    private var construction: Task<Value, any Error>?

    func load(
        constructing makeValue: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        if let construction {
            return try await construction.value
        }
        let construction = Task { try await makeValue() }
        self.construction = construction
        return try await construction.value
    }
}
