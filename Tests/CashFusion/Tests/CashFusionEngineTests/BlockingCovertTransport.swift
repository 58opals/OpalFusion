// BlockingCovertTransport.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
actor BlockingCovertTransport: OpalFusion.Runtime.CovertTransporting {
    private var preparedPlans: [OpalFusion.Runtime.CovertPreparationPlan] = []
    private var performedRequests: [OpalFusion.Runtime.CovertRequest] = []
    private var resetCount: Int = 0
    private let blocksPrepare: Bool
    private let blocksPerform: Bool
    private var prepareContinuation: CheckedContinuation<Result<Void, Error>, Never>?
    private var releasedPerformResult: Result<[UInt8], Error>?
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
            let result = await withCheckedContinuation { continuation in
                prepareContinuation = continuation
            }
            switch result {
            case .success:
                break
            case let .failure(error):
                throw error
            }
        }
    }

    func perform(_ request: OpalFusion.Runtime.CovertRequest) async throws -> [UInt8] {
        performedRequests.append(request)

        if blocksPerform {
            let result: Result<[UInt8], Error>
            if let releasedPerformResult {
                result = releasedPerformResult
            } else {
                result = await withCheckedContinuation { continuation in
                    performContinuation = continuation
                }
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

    func failPreparation(_ error: Error) {
        prepareContinuation?.resume(returning: .failure(error))
        prepareContinuation = nil
    }

    func releasePerform(response responseBytes: [UInt8]) {
        releasedPerformResult = .success(responseBytes)
        performContinuation?.resume(returning: .success(responseBytes))
        performContinuation = nil
    }

    func failPerform(_ error: Error) {
        releasedPerformResult = .failure(error)
        performContinuation?.resume(returning: .failure(error))
        performContinuation = nil
    }

    var recordedPreparationPlans: [OpalFusion.Runtime.CovertPreparationPlan] {
        preparedPlans
    }

    var recordedRequests: [OpalFusion.Runtime.CovertRequest] {
        performedRequests
    }

    var recordedResetCount: Int {
        resetCount
    }
}
