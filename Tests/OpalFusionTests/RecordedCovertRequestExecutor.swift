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
            throw LiveRuntimeTestHarnessError.inboundStreamClosed
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        ) else {
            throw LiveRuntimeTestHarnessError.invalidHTTPResponse(
                "Recorded covert response status code was invalid"
            )
        }
        return (responseData, response)
    }

    var recordedRequests: [URLRequest] {
        requests
    }
}
