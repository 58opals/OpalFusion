// RecordedCovertRequestExecutor.swift

import Foundation

actor RecordedCovertRequestExecutor {
    private let responseData: Data
    private let statusCode: Int
    private var requests: [URLRequest] = []

    init(
        responseData: Data,
        statusCode: Int = 200
    ) {
        self.responseData = responseData
        self.statusCode = statusCode
        self.requests = []
    }

    func execute(
        session _: URLSession,
        request: URLRequest
    ) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard let url = request.url else {
            throw LiveRuntimeTestSupportError.inboundStreamClosed
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}
