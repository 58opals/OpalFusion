// MosaicMainnetAlphaMaterialKeyData.swift

struct MosaicMainnetAlphaMaterialKeyData: Hashable, Sendable {
    let manifestBytes: [UInt8]
    let attemptIdentifier: [UInt8]
    let generationIdentifier: [UInt8]
    let localContributor: [UInt8]
    let localMaterialIdentifier: [UInt8]
}
