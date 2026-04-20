// BlockingCovertTransport.swift

@testable import OpalFusion

actor BlockingCovertTransport: OpalFusion.Runtime.CovertTransporting {
    private var preparedPlans: [OpalFusion.Runtime.CovertPreparationPlan] = []
    private var performedRequests: [OpalFusion.Runtime.CovertRequest] = []
    private var resetCount: Int = 0
    private let blocksPrepare: Bool
    private let blocksPerform: Bool
    private var prepareContinuation: CheckedContinuation<Void, Never>?
    private var performContinuation: CheckedContinuation<Result<[UInt8], Error>, Never>?

    init(
        blocksPrepare: Bool = false,
        blocksPerform: Bool = false
    ) {
        self.blocksPrepare = blocksPrepare
        self.blocksPerform = blocksPerform
        self.prepareContinuation = nil
        self.performContinuation = nil
    }

    func prepare(_ plan: OpalFusion.Runtime.CovertPreparationPlan) async throws {
        preparedPlans.append(plan)

        if blocksPrepare {
            await withCheckedContinuation { continuation in
                prepareContinuation = continuation
            }
        }
    }

    func perform(_ request: OpalFusion.Runtime.CovertRequest) async throws -> [UInt8] {
        performedRequests.append(request)

        if blocksPerform {
            let result = await withCheckedContinuation { continuation in
                performContinuation = continuation
            }
            switch result {
            case let .success(responseBytes):
                return responseBytes
            case let .failure(error):
                throw error
            }
        }

        return []
    }

    func reset() async {
        resetCount += 1
    }

    func releasePrepare() {
        prepareContinuation?.resume()
        prepareContinuation = nil
    }

    func releasePerform(response responseBytes: [UInt8]) {
        performContinuation?.resume(returning: .success(responseBytes))
        performContinuation = nil
    }

    func failPerform(_ error: Error) {
        performContinuation?.resume(returning: .failure(error))
        performContinuation = nil
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
