// ExternalInputComponentFixture.swift

@testable import OpalFusion

struct ExternalInputComponentFixture {
    let serializedComponent: [UInt8]
    let initialCommitment: OpalFusion.Commitment.InitialCommitment
    let communicationPrivateKey: [UInt8]
    let salt: [UInt8]
    let pedersenNonce: [UInt8]
}
