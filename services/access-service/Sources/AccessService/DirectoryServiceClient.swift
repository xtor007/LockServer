import Foundation
import LockServerContracts
import LockServerCore
import Vapor

struct DirectoryServiceClient {
    private let serviceClient: ServiceClient

    init(client: Client, baseURL: String) {
        serviceClient = ServiceClient(client: client, baseURL: baseURL)
    }

    func employer(id: UUID) async throws -> EmployerModel {
        try await serviceClient.get("/internal/directory/employers/\(id.uuidString)")
    }

    func employers() async throws -> [EmployerModel] {
        let response: DirectoryEmployersResponse = try await serviceClient.get("/internal/directory/employers")
        return response.employers
    }

    func cardOwnerID(code: String) async throws -> UUID? {
        let response: CredentialLookupResponse = try await serviceClient.get(
            "/internal/directory/cards/lookup",
            query: ["code": code]
        )
        return response.employerID
    }

    func fingerOwnerID(code: String) async throws -> UUID? {
        let response: CredentialLookupResponse = try await serviceClient.get(
            "/internal/directory/fingers/lookup",
            query: ["code": code]
        )
        return response.employerID
    }
}
