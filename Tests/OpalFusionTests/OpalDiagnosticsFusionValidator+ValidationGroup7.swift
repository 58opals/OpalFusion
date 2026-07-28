// OpalDiagnosticsFusionValidator+ValidationGroup7.swift

@testable import OpalFusion
import OpalDiagnostics
import Testing

extension OpalDiagnosticsFusionValidator {
    @Test("Operational diagnostics explicitly classify safe fields as public")
    func validateOperationalDiagnosticFieldPrivacy() {
        let fields: [OpalDiagnostics.Field] = [
            .payloadByteCount(1),
            .frameByteCount(2),
            .retryAttempt(3),
            .retryDelayMilliseconds(4),
            .terminal(true)
        ]

        #expect(fields.allSatisfy { $0.privacy == .public })
    }

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
