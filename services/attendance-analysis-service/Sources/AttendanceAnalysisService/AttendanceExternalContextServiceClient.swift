import Foundation
import LockServerContracts
import LockServerCore
import Vapor

struct AttendanceExternalContextServiceClient {
    private let serviceClient: ServiceClient

    init(client: Client, baseURL: String) {
        self.serviceClient = ServiceClient(client: client, baseURL: baseURL)
    }

    func resolveTraffic(day: String, arrivalTime: Date) async throws -> TrafficContextResolvedValue {
        try await serviceClient.post(
            "/internal/external-context/traffic/resolve",
            body: TrafficContextResolveRequest(day: day, arrivalTime: arrivalTime)
        )
    }

    func resolvePower(day: String, arrivalTime: Date) async throws -> PowerContextResolvedValue {
        try await serviceClient.post(
            "/internal/external-context/power/resolve",
            body: PowerContextResolveRequest(day: day, arrivalTime: arrivalTime)
        )
    }

    func resolveWeather(day: String, arrivalTime: Date) async throws -> WeatherContextResolvedValue {
        try await serviceClient.post(
            "/internal/external-context/weather/resolve",
            body: WeatherContextResolveRequest(day: day, arrivalTime: arrivalTime)
        )
    }
}
