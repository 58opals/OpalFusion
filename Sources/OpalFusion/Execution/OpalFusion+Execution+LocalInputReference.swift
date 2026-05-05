// OpalFusion+Execution+LocalInputReference.swift

import OpalCrypto

extension OpalFusion.Execution {
    struct LocalInputReference: Sendable {
        let transactionInputIndex: Int
        let componentIndex: Int
        let reservationInputIndex: Int
        let originalSlot: Int
        let participantInput: OpalFusion.Host.ParticipantInput
    }
}
