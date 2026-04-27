import LockServerContracts
import Vapor

struct ExternalContextController: RouteCollection {
    private let manager: ExternalContextManager
    private let authClient: AttendanceAuthServiceClient

    init(manager: ExternalContextManager, authClient: AttendanceAuthServiceClient) {
        self.manager = manager
        self.authClient = authClient
    }

    func boot(routes: RoutesBuilder) throws {
        let externalContext = routes.grouped("internal", "external-context")
        externalContext.get(":day", use: getContextsForDay)
        externalContext.get(":day", ":factor", use: getContextForFactor)
        externalContext.post("traffic", "resolve", use: resolveTraffic)
        externalContext.post("power", "resolve", use: resolvePower)
        externalContext.post("weather", "resolve", use: resolveWeather)
    }

    private func getContextsForDay(req: Request) async throws -> ExternalContextDayResponse {
        let context = try await authClient.authenticatedContext(headers: req.headers)
        guard context.isAdmin else {
            throw Abort(.forbidden, reason: "Admin token required")
        }
        let day = try req.parameters.require("day")
        return try await manager.contexts(for: day, on: req.db)
    }

    private func getContextForFactor(req: Request) async throws -> ExternalContextFactorResponse {
        let context = try await authClient.authenticatedContext(headers: req.headers)
        guard context.isAdmin else {
            throw Abort(.forbidden, reason: "Admin token required")
        }
        let day = try req.parameters.require("day")
        let factor = try req.parameters.require("factor")
        return try await manager.context(for: day, factorString: factor, on: req.db)
    }

    private func resolveTraffic(req: Request) async throws -> TrafficContextResolvedValue {
        let payload = try req.content.decode(TrafficContextResolveRequest.self)
        return try await manager.resolveTraffic(payload, on: req.db)
    }

    private func resolvePower(req: Request) async throws -> PowerContextResolvedValue {
        let payload = try req.content.decode(PowerContextResolveRequest.self)
        return try await manager.resolvePower(payload, on: req.db)
    }

    private func resolveWeather(req: Request) async throws -> WeatherContextResolvedValue {
        let payload = try req.content.decode(WeatherContextResolveRequest.self)
        return try await manager.resolveWeather(payload, on: req.db)
    }
}
