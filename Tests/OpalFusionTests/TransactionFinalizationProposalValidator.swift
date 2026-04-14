// TransactionFinalizationProposalValidator.swift

import OpalFusion
import Testing

struct TransactionFinalizationProposalValidator {
    @Test("Transaction finalization proposal preserves the existing one-argument initializer")
    func validateLegacyInitializerShape() {
        let proposal = OpalFusion.Host.TransactionFinalizationProposal(
            unsignedTransactionBytes: [0x01, 0x02, 0x03]
        )

        #expect(proposal.unsignedTransactionBytes == [0x01, 0x02, 0x03])
        #expect(proposal.sessionHash == nil)
        #expect(proposal.expectedInputCount == nil)
        #expect(proposal.expectedOutputCount == nil)
        #expect(proposal.participantCount == nil)
    }

    @Test("Transaction finalization proposal stores optional round metadata additively")
    func validateOptionalRoundMetadata() {
        let proposal = OpalFusion.Host.TransactionFinalizationProposal(
            unsignedTransactionBytes: [0xAA, 0xBB],
            sessionHash: [0x10, 0x20, 0x30],
            expectedInputCount: 3,
            expectedOutputCount: 5,
            participantCount: 8
        )

        #expect(proposal.unsignedTransactionBytes == [0xAA, 0xBB])
        #expect(proposal.sessionHash == [0x10, 0x20, 0x30])
        #expect(proposal.expectedInputCount == 3)
        #expect(proposal.expectedOutputCount == 5)
        #expect(proposal.participantCount == 8)
    }
}
