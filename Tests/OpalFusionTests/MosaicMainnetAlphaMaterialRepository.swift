// MosaicMainnetAlphaMaterialRepository.swift

import Synchronization

enum MosaicMainnetAlphaMaterialRepository {
    typealias Material = MosaicMainnetAlphaFixtures.MaterializedPreparation

    private static let preparations = Mutex<[
        MosaicMainnetAlphaMaterialKeyData: Result<Material, any Error>
    ]>([:])

    static func load(
        for key: MosaicMainnetAlphaMaterialKeyData,
        constructing makeMaterial: () throws -> Material
    ) throws -> Material {
        if let result = preparations.withLock({ $0[key] }) {
            return try result.get()
        }
        // Construction stays outside the lock. Concurrent cold consumers may
        // prepare equivalent values, but every reader receives the first result.
        let candidate = Result { try makeMaterial() }
        let result = preparations.withLock { preparations in
            if let existing = preparations[key] { return existing }
            preparations[key] = candidate
            return candidate
        }
        return try result.get()
    }
}
