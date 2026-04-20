// ScriptedCovertTransport.swift

@testable import OpalFusion

actor ScriptedCovertTransport: OpalFusion.Runtime.CovertTransporting {
    private var preparedPlans: [OpalFusion.Runtime.CovertPreparationPlan] = []
    private var performedRequests: [OpalFusion.Runtime.CovertRequest] = []
    private var queuedResponses: [[UInt8]] = []
    private var resetCount: Int = 0

    func prepare(_ plan: OpalFusion.Runtime.CovertPreparationPlan) async throws {
        preparedPlans.append(plan)
    }

    func perform(_ request: OpalFusion.Runtime.CovertRequest) async throws -> [UInt8] {
        performedRequests.append(request)
        if queuedResponses.isEmpty {
            return []
        }
        return queuedResponses.removeFirst()
    }

    func reset() async {
        resetCount += 1
        queuedResponses = []
    }

    func enqueueResponse(_ response: [UInt8]) {
        queuedResponses.append(response)
    }

    func recordedPreparationPlans() -> [OpalFusion.Runtime.CovertPreparationPlan] {
        preparedPlans
    }

    func recordedRequests() -> [OpalFusion.Runtime.CovertRequest] {
        performedRequests
    }

    func recordedResetCount() -> Int {
        resetCount
    }
}
