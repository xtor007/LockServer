import Foundation
import LockServerContracts
import LockServerCore
import Vapor

struct AttendanceAuthServiceClient {
    private let serviceClient: ServiceClient
    private let decoder: JSONDecoder

    init(client: Client, baseURL: String) {
        self.serviceClient = ServiceClient(client: client, baseURL: baseURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func authenticatedContext(headers: HTTPHeaders) async throws -> AuthenticatedUserContext {
        guard let authorization = headers.first(name: .authorization) else {
            throw Abort(.unauthorized, reason: "Missing authorization header")
        }

        var forwardedHeaders = HTTPHeaders()
        forwardedHeaders.replaceOrAdd(name: .authorization, value: authorization)
        let response = try await serviceClient.send(method: .GET, path: "/internal/auth/context", headers: forwardedHeaders)

        guard response.status == .ok, let body = response.body else {
            throw Abort(.unauthorized, reason: "Invalid authorization token")
        }

        return try decoder.decode(AuthenticatedUserContext.self, from: Data(buffer: body))
    }
}
