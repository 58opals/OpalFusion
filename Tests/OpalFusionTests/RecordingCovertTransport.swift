// RecordingCovertTransport.swift

@testable import OpalFusion

actor RecordingCovertTransport: OpalFusion.Runtime.CovertTransporting {
    private let base: any OpalFusion.Runtime.CovertTransporting
    private let messageDecoder: OpalFusion.Wire.CovertMessageDecoder
    private(set) var preparationPlans: [OpalFusion.Runtime.CovertPreparationPlan]
    private(set) var requests: [OpalFusion.Runtime.CovertRequest]
    private(set) var requestPayloads: [[UInt8]]
    private(set) var responsePayloads: [[UInt8]]
    private(set) var requestMessages: [OpalFusion.ProtocolModel.CovertMessage]
    private(set) var responses: [OpalFusion.ProtocolModel.CovertResponse]
    private(set) var requestDecodeFailures: [String]
    private(set) var responseDecodeFailures: [String]

    init(base: any OpalFusion.Runtime.CovertTransporting) {
        self.base = base
        self.messageDecoder = .init()
        self.preparationPlans = []
        self.requests = []
        self.requestPayloads = []
        self.responsePayloads = []
        self.requestMessages = []
        self.responses = []
        self.requestDecodeFailures = []
        self.responseDecodeFailures = []
    }

    func prepare(_ plan: OpalFusion.Runtime.CovertPreparationPlan) async throws {
        try await base.prepare(plan)
        preparationPlans.append(plan)
    }

    func perform(_ request: OpalFusion.Runtime.CovertRequest) async throws -> [UInt8] {
        requests.append(request)
        requestPayloads.append(request.payload)
        do {
            requestMessages.append(try messageDecoder.decodeMessage(request.payload))
        } catch {
            requestDecodeFailures.append(String(describing: error))
        }

        let responseBytes = try await base.perform(request)
        responsePayloads.append(responseBytes)
        do {
            responses.append(try messageDecoder.decodeResponse(responseBytes))
        } catch {
            responseDecodeFailures.append(String(describing: error))
        }
        return responseBytes
    }

    func reset() async {
        await base.reset()
    }

    func recordedPreparationPlans() -> [OpalFusion.Runtime.CovertPreparationPlan] {
        preparationPlans
    }

    func recordedRequests() -> [OpalFusion.Runtime.CovertRequest] {
        requests
    }

    func recordedRequestPayloads() -> [[UInt8]] {
        requestPayloads
    }

    func recordedResponsePayloads() -> [[UInt8]] {
        responsePayloads
    }

    func recordedRequestMessages() -> [OpalFusion.ProtocolModel.CovertMessage] {
        requestMessages
    }

    func recordedResponses() -> [OpalFusion.ProtocolModel.CovertResponse] {
        responses
    }

    func recordedRequestDecodeFailures() -> [String] {
        requestDecodeFailures
    }

    func recordedResponseDecodeFailures() -> [String] {
        responseDecodeFailures
    }
}
