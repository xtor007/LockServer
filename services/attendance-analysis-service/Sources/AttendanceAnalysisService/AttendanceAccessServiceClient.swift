import Foundation
import LockServerContracts
import LockServerCore
import Vapor

struct AttendanceAccessServiceClient {
    private let serviceClient: ServiceClient

    init(client: Client, baseURL: String) {
        self.serviceClient = ServiceClient(client: client, baseURL: baseURL)
    }

    func logs(userId: UUID, context: AuthenticatedUserContext) async throws -> Logs {
        var headers = HTTPHeaders()
        headers.addAuthenticatedUserContext(context)
        return try await serviceClient.get("/internal/access/users/\(userId.uuidString)/logs", headers: headers)
    }
}
