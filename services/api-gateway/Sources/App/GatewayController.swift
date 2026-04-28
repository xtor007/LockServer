import Foundation
import LockServerContracts
import LockServerCore
import Vapor

struct GatewayController: RouteCollection {
    private let authBaseURL: String
    private let directoryBaseURL: String
    private let accessBaseURL: String
    private let attendanceAnalysisBaseURL: String
    private let externalContextBaseURL: String

    init(
        authBaseURL: String,
        directoryBaseURL: String,
        accessBaseURL: String,
        attendanceAnalysisBaseURL: String,
        externalContextBaseURL: String
    ) {
        self.authBaseURL = authBaseURL
        self.directoryBaseURL = directoryBaseURL
        self.accessBaseURL = accessBaseURL
        self.attendanceAnalysisBaseURL = attendanceAnalysisBaseURL
        self.externalContextBaseURL = externalContextBaseURL
    }

    func boot(routes: RoutesBuilder) throws {
        routes.get(use: root)
        routes.get("validate", use: validate)

        let auth = routes.grouped("auth")
        auth.get("getToken", use: getToken)
        auth.get("refresh", use: refreshToken)
        auth.post("changePasswordEmail", use: changePasswordEmail)
        auth.post("changePassword", use: changePassword)

        let verifier = routes.grouped("verifier")
        verifier.get("verifyCard", use: verifyCard)
        verifier.get("verifyFinger", use: verifyFinger)

        let info = routes.grouped("info")
        info.get(use: getInfo)
        info.post("logs", use: getLogs)
        info.get("statistic", use: getStatistic)
        info.get("all", use: getAll)

        let open = routes.grouped("open")
        open.get("open", use: openDoor)

        let command = routes.grouped("command")
        command.post("add", use: addUser)
        command.get("delete", use: deleteUser)

        let attendanceAnalysis = routes.grouped("internal", "attendance-analysis")
        attendanceAnalysis.post("observations", "run", use: runAttendanceObservation)
        attendanceAnalysis.post("observations", "rebuild", use: rebuildAttendanceObservation)
        attendanceAnalysis.post("observations", "run-all", use: runAttendanceObservationsForAllUsers)
        attendanceAnalysis.post("observations", "rebuild-all", use: rebuildAttendanceObservationsForAllUsers)
        attendanceAnalysis.post("clustering", "run", use: runAttendanceClustering)
        attendanceAnalysis.post("clustering", "rebuild", use: rebuildAttendanceClustering)
        attendanceAnalysis.post("mlp", "run", use: runAttendanceMLP)
        attendanceAnalysis.post("mlp", "rebuild", use: rebuildAttendanceMLP)
        attendanceAnalysis.get("users", ":id", "observations", use: getAttendanceObservations)
        attendanceAnalysis.get("users", ":id", "observations", ":day", use: getAttendanceObservation)
        attendanceAnalysis.get("users", ":id", "results", use: getAttendanceResults)

        let externalContext = routes.grouped("internal", "external-context")
        externalContext.get(":day", use: getExternalContextForDay)
        externalContext.get(":day", ":factor", use: getExternalContextForFactor)
    }

    private func root(req: Request) -> String {
        "ok"
    }

    private func validate(req: Request) -> ValidServerResponse {
        ValidServerResponse(isValid: true)
    }

    private func getToken(req: Request) async throws -> Response {
        try await forwardAuthRequest(req, path: "/auth/getToken")
    }

    private func refreshToken(req: Request) async throws -> Response {
        try await forwardAuthRequest(req, path: "/auth/refresh")
    }

    private func changePasswordEmail(req: Request) async throws -> Response {
        try await forwardAuthRequest(req, path: "/auth/changePasswordEmail")
    }

    private func changePassword(req: Request) async throws -> Response {
        try await forwardAuthRequest(req, path: "/auth/changePassword")
    }

    private func verifyCard(req: Request) async throws -> Response {
        let code = try req.query.get(String.self, at: "code")
        let service = ServiceClient(client: req.client, baseURL: accessBaseURL)
        let result = try await service.getString("/verifier/verifyCard", query: ["code": code])
        return textResponse(req, body: result)
    }

    private func verifyFinger(req: Request) async throws -> Response {
        let code = try req.query.get(String.self, at: "code")
        let service = ServiceClient(client: req.client, baseURL: accessBaseURL)
        let result = try await service.getString("/verifier/verifyFinger", query: ["code": code])
        return textResponse(req, body: result)
    }

    private func getInfo(req: Request) async throws -> EmployerModel {
        let context = try await authenticatedContext(for: req)
        var headers = HTTPHeaders()
        headers.addAuthenticatedUserContext(context)
        return try await ServiceClient(client: req.client, baseURL: accessBaseURL)
            .get("/info", headers: headers)
    }

    private func getLogs(req: Request) async throws -> Logs {
        let context = try await authenticatedContext(for: req)
        let body = try req.content.decode(GetLogsRequest.self)
        var headers = HTTPHeaders()
        headers.addAuthenticatedUserContext(context)
        return try await ServiceClient(client: req.client, baseURL: accessBaseURL)
            .post("/info/logs", body: body, headers: headers)
    }

    private func getStatistic(req: Request) async throws -> Statistic {
        let context = try await authenticatedContext(for: req)
        var headers = HTTPHeaders()
        headers.addAuthenticatedUserContext(context)
        return try await ServiceClient(client: req.client, baseURL: accessBaseURL)
            .get("/info/statistic", headers: headers)
    }

    private func getAll(req: Request) async throws -> Employers {
        let context = try await authenticatedContext(for: req)
        guard context.isAdmin else {
            throw Abort(.forbidden, reason: "Admin token required")
        }
        var headers = HTTPHeaders()
        headers.addAuthenticatedUserContext(context)
        return try await ServiceClient(client: req.client, baseURL: accessBaseURL)
            .get("/info/all", headers: headers)
    }

    private func openDoor(req: Request) async throws -> OpeningResult {
        let context = try await authenticatedContext(for: req)
        var headers = HTTPHeaders()
        headers.addAuthenticatedUserContext(context)
        return try await ServiceClient(client: req.client, baseURL: accessBaseURL)
            .get("/open/open", headers: headers)
    }

    private func addUser(req: Request) async throws -> ValidServerResponse {
        let context = try await authenticatedContext(for: req)
        guard context.isAdmin else {
            throw Abort(.forbidden, reason: "Admin token required")
        }

        let incomingEmployer = try req.content.decode(EmployerModel.self)
        guard let email = incomingEmployer.email else {
            throw Abort(.badRequest, reason: "Email is required")
        }

        let generatedID = incomingEmployer.id ?? UUID()
        let generatedPassword = RandomStringGenerator.alphanumeric(length: 8)
        let employer = EmployerModel(
            id: generatedID,
            isAdmin: incomingEmployer.isAdmin,
            name: incomingEmployer.name,
            surname: incomingEmployer.surname,
            department: incomingEmployer.department,
            email: email,
            workNormMinutes: incomingEmployer.workNormMinutes ?? SeedUsers.defaultWorkNormMinutes,
            hasCard: incomingEmployer.hasCard,
            hasFinger: incomingEmployer.hasFinger
        )

        let directoryClient = ServiceClient(client: req.client, baseURL: directoryBaseURL)
        let authClient = ServiceClient(client: req.client, baseURL: authBaseURL)

        _ = try await directoryClient.post(
            "/internal/directory/employers",
            body: DirectoryEmployerUpsertRequest(employer: employer),
            as: ValidServerResponse.self
        )

        do {
            _ = try await authClient.post(
                "/internal/auth/users",
                body: AuthUserUpsertRequest(
                    id: generatedID,
                    email: email,
                    password: generatedPassword,
                    isAdmin: employer.isAdmin,
                    sendWelcomeEmail: true
                ),
                as: ValidServerResponse.self
            )
        } catch {
            _ = try? await directoryClient.delete("/internal/directory/employers/\(generatedID.uuidString)", as: ValidServerResponse.self)
            throw error
        }

        return ValidServerResponse(isValid: true)
    }

    private func deleteUser(req: Request) async throws -> ValidServerResponse {
        let context = try await authenticatedContext(for: req)
        guard context.isAdmin else {
            throw Abort(.forbidden, reason: "Admin token required")
        }

        let idString = try req.query.get(String.self, at: "id")
        guard let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest, reason: "Invalid user id")
        }

        let directoryClient = ServiceClient(client: req.client, baseURL: directoryBaseURL)
        let accessClient = ServiceClient(client: req.client, baseURL: accessBaseURL)
        let authClient = ServiceClient(client: req.client, baseURL: authBaseURL)

        let employer: EmployerModel = try await directoryClient.get("/internal/directory/employers/\(id.uuidString)")
        guard employer.isAdmin == false else {
            throw Abort(.forbidden, reason: "Admin user cannot be deleted")
        }

        _ = try await accessClient.delete("/internal/access/logs/\(id.uuidString)", as: ValidServerResponse.self)
        _ = try await authClient.delete("/internal/auth/users/\(id.uuidString)", as: ValidServerResponse.self)
        _ = try await directoryClient.delete("/internal/directory/employers/\(id.uuidString)", as: ValidServerResponse.self)

        return ValidServerResponse(isValid: true)
    }

    private func runAttendanceObservation(req: Request) async throws -> Response {
        try await forwardAttendanceRequest(req, path: "/internal/attendance-analysis/observations/run")
    }

    private func rebuildAttendanceObservation(req: Request) async throws -> Response {
        try await forwardAttendanceRequest(req, path: "/internal/attendance-analysis/observations/rebuild")
    }

    private func runAttendanceObservationsForAllUsers(req: Request) async throws -> Response {
        try await forwardAttendanceRequest(req, path: "/internal/attendance-analysis/observations/run-all")
    }

    private func rebuildAttendanceObservationsForAllUsers(req: Request) async throws -> Response {
        try await forwardAttendanceRequest(req, path: "/internal/attendance-analysis/observations/rebuild-all")
    }

    private func runAttendanceClustering(req: Request) async throws -> Response {
        try await forwardAttendanceRequest(req, path: "/internal/attendance-analysis/clustering/run")
    }

    private func rebuildAttendanceClustering(req: Request) async throws -> Response {
        try await forwardAttendanceRequest(req, path: "/internal/attendance-analysis/clustering/rebuild")
    }

    private func runAttendanceMLP(req: Request) async throws -> Response {
        try await forwardAttendanceRequest(req, path: "/internal/attendance-analysis/mlp/run")
    }

    private func rebuildAttendanceMLP(req: Request) async throws -> Response {
        try await forwardAttendanceRequest(req, path: "/internal/attendance-analysis/mlp/rebuild")
    }

    private func getAttendanceObservations(req: Request) async throws -> Response {
        let id = try req.parameters.require("id")
        return try await forwardAttendanceRequest(req, path: "/internal/attendance-analysis/users/\(id)/observations")
    }

    private func getAttendanceObservation(req: Request) async throws -> Response {
        let id = try req.parameters.require("id")
        let day = try req.parameters.require("day")
        return try await forwardAttendanceRequest(req, path: "/internal/attendance-analysis/users/\(id)/observations/\(day)")
    }

    private func getAttendanceResults(req: Request) async throws -> Response {
        let id = try req.parameters.require("id")
        return try await forwardAttendanceRequest(req, path: "/internal/attendance-analysis/users/\(id)/results")
    }

    private func getExternalContextForDay(req: Request) async throws -> Response {
        let day = try req.parameters.require("day")
        return try await forwardExternalContextRequest(req, path: "/internal/external-context/\(day)")
    }

    private func getExternalContextForFactor(req: Request) async throws -> Response {
        let day = try req.parameters.require("day")
        let factor = try req.parameters.require("factor")
        return try await forwardExternalContextRequest(req, path: "/internal/external-context/\(day)/\(factor)")
    }
}

private extension GatewayController {
    func authenticatedContext(for req: Request) async throws -> AuthenticatedUserContext {
        guard let authorization = req.headers.first(name: .authorization) else {
            throw Abort(.unauthorized, reason: "Missing authorization header")
        }

        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .authorization, value: authorization)
        return try await ServiceClient(client: req.client, baseURL: authBaseURL)
            .get("/internal/auth/context", headers: headers)
    }

    func forwardAuthRequest(_ req: Request, path: String) async throws -> Response {
        try await forwardRequest(req, baseURL: authBaseURL, path: path)
    }

    func forwardAttendanceRequest(_ req: Request, path: String) async throws -> Response {
        try await forwardRequest(req, baseURL: attendanceAnalysisBaseURL, path: path)
    }

    func forwardExternalContextRequest(_ req: Request, path: String) async throws -> Response {
        try await forwardRequest(req, baseURL: externalContextBaseURL, path: path)
    }

    func forwardRequest(_ req: Request, baseURL: String, path: String) async throws -> Response {
        let response = try await req.client.send(req.method, headers: req.headers, to: URI(string: baseURL + path)) { request in
            request.body = req.body.data
        }
        return try makeResponse(from: response, for: req)
    }

    func makeResponse(from response: ClientResponse, for req: Request) throws -> Response {
        let vaporResponse = Response(status: response.status, headers: response.headers)
        if let body = response.body {
            vaporResponse.body = .init(buffer: body)
        }

        guard response.status.code < 400 else {
            let reason = response.body.flatMap { buffer in
                buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes)
            } ?? HTTPResponseStatus(statusCode: Int(response.status.code)).reasonPhrase
            throw Abort(response.status, reason: reason)
        }

        return vaporResponse
    }

    func textResponse(_ req: Request, body: String) -> Response {
        let response = Response(status: .ok)
        response.headers.replaceOrAdd(name: .contentType, value: "text/plain; charset=utf-8")
        response.body = .init(string: body)
        return response
    }
}
