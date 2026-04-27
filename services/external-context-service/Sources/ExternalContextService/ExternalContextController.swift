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
    }

    private func getContextsForDay(req: Request) async throws -> ExternalContextDayResponse {
        let day = try req.parameters.require("day")

        if internalRequestSource(req) == "attendance-analysis" {
            guard let arrivalTime = try arrivalTimeQuery(req) else {
                throw Abort(.badRequest, reason: "arrivalTime query is required for internal day materialization")
            }
            return try await manager.contexts(for: day, arrivalTime: arrivalTime, materializeIfNeeded: true, on: req.db)
        }

        let context = try await authClient.authenticatedContext(headers: req.headers)
        guard context.isAdmin else {
            throw Abort(.forbidden, reason: "Admin token required")
        }
        return try await manager.contexts(for: day, arrivalTime: nil, materializeIfNeeded: false, on: req.db)
    }

    private func getContextForFactor(req: Request) async throws -> ExternalContextFactorResponse {
        let day = try req.parameters.require("day")
        let factor = try req.parameters.require("factor")

        let context = try await authClient.authenticatedContext(headers: req.headers)
        guard context.isAdmin else {
            throw Abort(.forbidden, reason: "Admin token required")
        }
        return try await manager.context(for: day, factorString: factor, on: req.db)
    }
}

private extension ExternalContextController {
    func internalRequestSource(_ req: Request) -> String? {
        req.headers.first(name: "X-LockServer-Internal-Service")
    }

    func arrivalTimeQuery(_ req: Request) throws -> Date? {
        guard let rawValue = try? req.query.get(String.self, at: "arrivalTime") else {
            return nil
        }
        guard let date = Self.iso8601Formatter.date(from: rawValue) else {
            throw Abort(.badRequest, reason: "arrivalTime query must use ISO-8601 format")
        }
        return date
    }

    static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
