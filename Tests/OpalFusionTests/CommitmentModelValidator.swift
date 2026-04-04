// CommitmentModelValidator.swift

import OpalFusion
import Testing

struct CommitmentModelValidator {
    @Test("Commitment models preserve payload cases and byte values")
    func validateCommitmentModels() {
        let inputComponent = OpalFusion.Commitment.InputComponent(
            outpointTransactionHash: [0xAA, 0xBB],
            outpointIndex: 2,
            publicKey: [0x02, 0x03],
            amountSatoshis: 42_000
        )
        let outputComponent = OpalFusion.Commitment.OutputComponent(
            lockingScript: [0x76, 0xA9],
            amountSatoshis: 21_000
        )
        let blankComponent = OpalFusion.Commitment.BlankComponent()
        let inputPayload = OpalFusion.Commitment.ComponentPayload.input(inputComponent)
        let outputPayload = OpalFusion.Commitment.ComponentPayload.output(outputComponent)
        let blankPayload = OpalFusion.Commitment.ComponentPayload.blank(blankComponent)
        let component = OpalFusion.Commitment.Component(
            saltCommitment: [0x10, 0x11],
            payload: inputPayload
        )
        let initialCommitment = OpalFusion.Commitment.InitialCommitment(
            saltedComponentHash: [0x20, 0x21],
            amountCommitment: [0x30, 0x31],
            communicationPublicKey: [0x02, 0x99]
        )

        #expect(Self.requireSendable(inputComponent) == inputComponent)
        #expect(inputPayload == .input(inputComponent))
        #expect(outputPayload == .output(outputComponent))
        #expect(blankPayload == .blank(blankComponent))
        #expect(component.saltCommitment == [0x10, 0x11])
        #expect(component.payload == inputPayload)
        #expect(initialCommitment.saltedComponentHash == [0x20, 0x21])
        #expect(initialCommitment.amountCommitment == [0x30, 0x31])
        #expect(initialCommitment.communicationPublicKey == [0x02, 0x99])
    }

    static func requireSendable<Value: Sendable>(_ value: Value) -> Value {
        value
    }
}
