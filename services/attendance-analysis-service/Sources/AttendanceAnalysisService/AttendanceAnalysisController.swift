import LockServerContracts
import Vapor

struct AttendanceAnalysisController: RouteCollection {
    private let manager: AttendanceAnalysisManager
    private let authClient: AttendanceAuthServiceClient

    init(manager: AttendanceAnalysisManager, authClient: AttendanceAuthServiceClient) {
        self.manager = manager
        self.authClient = authClient
    }

    func boot(routes: RoutesBuilder) throws {
        let attendanceAnalysis = routes.grouped("internal", "attendance-analysis")
        attendanceAnalysis.post("observations", "run", use: runObservation)
        attendanceAnalysis.post("observations", "rebuild", use: rebuildObservation)
        attendanceAnalysis.post("observations", "run-all", use: runObservationsForAllUsers)
        attendanceAnalysis.post("observations", "rebuild-all", use: rebuildObservationsForAllUsers)
        attendanceAnalysis.post("clustering", "run", use: runClustering)
        attendanceAnalysis.post("clustering", "rebuild", use: rebuildClustering)
        attendanceAnalysis.get("users", ":id", "observations", use: getObservations)
        attendanceAnalysis.get("users", ":id", "observations", ":day", use: getObservation)
        attendanceAnalysis.get("users", ":id", "results", use: getResults)
    }

    private func runObservation(req: Request) async throws -> AttendanceObservationRunResponse {
        let context = try await authClient.authenticatedContext(headers: req.headers)
        guard context.isAdmin else {
            throw Abort(.forbidden, reason: "Admin token required")
        }
        let payload = try req.content.decode(AttendanceObservationCommandRequest.self)
        return try await manager.runObservation(userId: payload.userId, dayString: payload.day, rebuild: false, context: context, on: req.db)
    }

    private func rebuildObservation(req: Request) async throws -> AttendanceObservationRunResponse {
        let context = try await authClient.authenticatedContext(headers: req.headers)
        guard context.isAdmin else {
            throw Abort(.forbidden, reason: "Admin token required")
        }
        let payload = try req.content.decode(AttendanceObservationCommandRequest.self)
        return try await manager.runObservation(userId: payload.userId, dayString: payload.day, rebuild: true, context: context, on: req.db)
    }

    private func runObservationsForAllUsers(req: Request) async throws -> AttendanceObservationBatchResponse {
        let context = try await authClient.authenticatedContext(headers: req.headers)
        guard context.isAdmin else {
            throw Abort(.forbidden, reason: "Admin token required")
        }
        let payload = try req.content.decode(AttendanceObservationBatchCommandRequest.self)
        return try await manager.runObservationsForAllUsers(dayString: payload.day, rebuild: false, context: context, on: req.db)
    }

    private func rebuildObservationsForAllUsers(req: Request) async throws -> AttendanceObservationBatchResponse {
        let context = try await authClient.authenticatedContext(headers: req.headers)
        guard context.isAdmin else {
            throw Abort(.forbidden, reason: "Admin token required")
        }
        let payload = try req.content.decode(AttendanceObservationBatchCommandRequest.self)
        return try await manager.runObservationsForAllUsers(dayString: payload.day, rebuild: true, context: context, on: req.db)
    }

    private func runClustering(req: Request) async throws -> AttendanceClusteringRunResponse {
        let context = try await authClient.authenticatedContext(headers: req.headers)
        guard context.isAdmin else {
            throw Abort(.forbidden, reason: "Admin token required")
        }
        let payload = try req.content.decode(AttendanceClusteringCommandRequest.self)
        return try await manager.runClustering(dayString: payload.day, userId: payload.userId, rebuild: false, on: req.db)
    }

    private func rebuildClustering(req: Request) async throws -> AttendanceClusteringRunResponse {
        let context = try await authClient.authenticatedContext(headers: req.headers)
        guard context.isAdmin else {
            throw Abort(.forbidden, reason: "Admin token required")
        }
        let payload = try req.content.decode(AttendanceClusteringCommandRequest.self)
        return try await manager.runClustering(dayString: payload.day, userId: payload.userId, rebuild: true, on: req.db)
    }

    private func getObservations(req: Request) async throws -> AttendanceDayObservationsResponse {
        let context = try await authClient.authenticatedContext(headers: req.headers)
        let userId = try req.parameters.require("id", as: UUID.self)
        guard context.id == userId || context.isAdmin else {
            throw Abort(.forbidden, reason: "No access to requested attendance observations")
        }
        return AttendanceDayObservationsResponse(observations: try await manager.observations(userId: userId, on: req.db))
    }

    private func getObservation(req: Request) async throws -> AttendanceDayObservationResponse {
        let context = try await authClient.authenticatedContext(headers: req.headers)
        let userId = try req.parameters.require("id", as: UUID.self)
        guard context.id == userId || context.isAdmin else {
            throw Abort(.forbidden, reason: "No access to requested attendance observations")
        }
        let day = try req.parameters.require("day")
        return try await manager.observation(userId: userId, dayString: day, on: req.db)
    }

    private func getResults(req: Request) async throws -> AttendanceAnalysisResultsResponse {
        let context = try await authClient.authenticatedContext(headers: req.headers)
        let userId = try req.parameters.require("id", as: UUID.self)
        guard context.id == userId || context.isAdmin else {
            throw Abort(.forbidden, reason: "No access to requested attendance results")
        }
        return AttendanceAnalysisResultsResponse(results: try await manager.results(userId: userId, on: req.db))
    }
}
