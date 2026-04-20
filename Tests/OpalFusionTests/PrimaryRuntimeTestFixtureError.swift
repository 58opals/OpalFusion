// PrimaryRuntimeTestFixtureError.swift

enum PrimaryRuntimeTestFixtureError: Swift.Error, Equatable {
    case expectedSinglePayload(Int)
    case expectedWriteEffect
    case expectedCovertRequestEffect
}
