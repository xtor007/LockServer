import LockServerContracts
import LockServerCore
import Vapor

struct DeviceServiceClient {
    private let serviceClient: ServiceClient

    init(client: Client, baseURL: String) {
        serviceClient = ServiceClient(client: client, baseURL: baseURL)
    }

    func open() async throws -> OpeningResult {
        try await serviceClient.post("/internal/device/open", body: EmptyPayload())
    }
}

private struct EmptyPayload: Content { }
