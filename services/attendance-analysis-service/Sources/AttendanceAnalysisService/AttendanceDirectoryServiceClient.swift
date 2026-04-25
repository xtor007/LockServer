import Foundation
import LockServerContracts
import LockServerCore
import Vapor

struct AttendanceDirectoryServiceClient {
    private let serviceClient: ServiceClient

    init(client: Client, baseURL: String) {
        self.serviceClient = ServiceClient(client: client, baseURL: baseURL)
    }

    func employer(id: UUID) async throws -> EmployerModel {
        try await serviceClient.get("/internal/directory/employers/\(id.uuidString)")
    }

    func employers() async throws -> [EmployerModel] {
        let response: DirectoryEmployersResponse = try await serviceClient.get("/internal/directory/employers")
        return response.employers
    }
}
