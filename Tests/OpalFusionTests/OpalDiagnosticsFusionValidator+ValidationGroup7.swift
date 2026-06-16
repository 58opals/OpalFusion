// OpalDiagnosticsFusionValidator+ValidationGroup7.swift

@testable import OpalFusion
import OpalDiagnostics
import Testing

extension OpalDiagnosticsFusionValidator {
    @Test("Workflow failure diagnostics keep branch and reason mappings together")
    func validateWorkflowFailureDiagnosticFields() throws {
        let fields = OpalDiagnostics.Field.workflowFailureFields(
            for: .protocolValidationFailed("invalid shared component")
        )

        #expect(fields.count == 2)
        let validationBranch = try #require(fields.first { $0.name == "validation_branch" })
        let reasonCode = try #require(fields.first { $0.name == "reason_code" })
        #expect(validationBranch.value == "protocol_validation")
        #expect(reasonCode.value == "workflow_protocol_validation_failed")
    }
}
