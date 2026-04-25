import Fluent
import LockServerContracts
import LockServerCore
import Vapor

struct AccessController: RouteCollection {
    private let directoryClient: DirectoryServiceClient
    private let deviceClient: DeviceServiceClient
    private let eventRecorder: DomainEventRecorder

    init(directoryClient: DirectoryServiceClient, deviceClient: DeviceServiceClient, eventRecorder: DomainEventRecorder) {
        self.directoryClient = directoryClient
        self.deviceClient = deviceClient
        self.eventRecorder = eventRecorder
    }

    func boot(routes: RoutesBuilder) throws {
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

        let `internal` = routes.grouped("internal", "access")
        `internal`.delete("logs", ":id", use: deleteLogs)
    }

    private func verifyCard(req: Request) async throws -> String {
        guard let code = try? req.query.get(String.self, at: "code") else {
            return "0"
        }

        guard let employerID = try await directoryClient.cardOwnerID(code: code) else {
            await eventRecorder.publish("access.denied", payload: ["method": "card", "code": code])
            return "0"
        }

        try await addEnter(for: employerID, on: req.db)
        await eventRecorder.publish("access.granted", payload: ["method": "card", "code": code, "employerId": employerID.uuidString])
        return "1"
    }

    private func verifyFinger(req: Request) async throws -> String {
        guard let code = try? req.query.get(String.self, at: "code"),
              let employerID = try await directoryClient.fingerOwnerID(code: code) else {
            await eventRecorder.publish("access.denied", payload: ["method": "finger"])
            return "0"
        }

        try await addEnter(for: employerID, on: req.db)
        await eventRecorder.publish("access.granted", payload: ["method": "finger", "code": code, "employerId": employerID.uuidString])
        return "1"
    }

    private func getInfo(req: Request) async throws -> EmployerModel {
        let context = try AuthenticatedUserContext(headers: req.headers)
        return try await directoryClient.employer(id: context.id)
    }

    private func getLogs(req: Request) async throws -> Logs {
        let context = try AuthenticatedUserContext(headers: req.headers)
        let request = try req.content.decode(GetLogsRequest.self)
        let targetID = request.id ?? context.id

        guard targetID == context.id || context.isAdmin else {
            throw Abort(.forbidden, reason: "No access to requested logs")
        }

        let logs = try await logs(for: targetID, after: request.afterDate, on: req.db)
        return Logs(logs: logs)
    }

    private func getStatistic(req: Request) async throws -> Statistic {
        let context = try AuthenticatedUserContext(headers: req.headers)
        let logs = try await logs(for: context.id, after: nil, on: req.db)
        return Statistic(averageTime: StatisticCalculator(enters: logs).averageTime)
    }

    private func getAll(req: Request) async throws -> Employers {
        let context = try AuthenticatedUserContext(headers: req.headers)
        guard context.isAdmin else {
            throw Abort(.forbidden, reason: "Admin token required")
        }

        let employers = try await directoryClient.employers()
        var result = [EmployerWithStatistic]()

        for employer in employers {
            guard let employerID = employer.id else {
                continue
            }
            let logs = try await logs(for: employerID, after: nil, on: req.db)
            let statistic = Statistic(averageTime: StatisticCalculator(enters: logs).averageTime)
            result.append(EmployerWithStatistic(employer: employer, statistic: statistic))
        }

        return Employers(employers: result)
    }

    private func openDoor(req: Request) async throws -> OpeningResult {
        let context = try AuthenticatedUserContext(headers: req.headers)
        await eventRecorder.publish("door.open.requested", payload: ["employerId": context.id.uuidString])
        let result = try await deviceClient.open()
        if result.isSuccess {
            try await addEnter(for: context.id, on: req.db)
            await eventRecorder.publish("door.opened", payload: ["employerId": context.id.uuidString])
        }
        return result
    }

    private func deleteLogs(req: Request) async throws -> ValidServerResponse {
        let id = try req.parameters.require("id", as: UUID.self)
        try await AccessEnter.query(on: req.db)
            .filter(\.$employerID == id)
            .delete()
        return ValidServerResponse(isValid: true)
    }
}

private extension AccessController {
    func addEnter(for employerID: UUID, on database: Database) async throws {
        let lastEnter = try await AccessEnter.query(on: database)
            .filter(\.$employerID == employerID)
            .sort(\.$time, .descending)
            .first()
        let isOn = !(lastEnter?.isOn ?? false)
        let newEnter = AccessEnter(employerID: employerID, isOn: isOn)
        try await newEnter.create(on: database)
    }

    func logs(for employerID: UUID, after date: Date?, on database: Database) async throws -> [EnterModel] {
        let enters = try await AccessEnter.query(on: database)
            .filter(\.$employerID == employerID)
            .filter(\.$time > (date ?? .distantPast))
            .sort(\.$time, .ascending)
            .all()

        return enters.map {
            EnterModel(isOn: $0.isOn, time: $0.time)
        }
    }
}
