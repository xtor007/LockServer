import Foundation
import LockServerContracts
import LockServerCore
import Vapor

struct AttendanceExternalContextServiceClient {
    private let serviceClient: ServiceClient

    init(client: Client, baseURL: String) {
        self.serviceClient = ServiceClient(client: client, baseURL: baseURL)
    }

    func dayContext(day: String, arrivalTime: Date) async throws -> ExternalContextDayResponse {
        try await serviceClient.get(
            "/internal/external-context/\(day)",
            headers: internalHeaders,
            query: ["arrivalTime": iso8601String(from: arrivalTime)],
            as: ExternalContextDayResponse.self
        )
    }
}

private extension AttendanceExternalContextServiceClient {
    var internalHeaders: HTTPHeaders {
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: "X-LockServer-Internal-Service", value: "attendance-analysis")
        return headers
    }

    func iso8601String(from date: Date) -> String {
        Self.formatter.string(from: date)
    }

    static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
