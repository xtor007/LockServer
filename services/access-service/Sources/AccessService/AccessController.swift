import Fluent
import LockServerContracts
import LockServerCore
import SQLKit
import Vapor

struct AccessController: RouteCollection {
    private let directoryClient: DirectoryServiceClient
    private let deviceClient: DeviceServiceClient
    private let eventRecorder: DomainEventRecorder
    private let statisticsAggregator = AccessStatisticsAggregator()

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
        `internal`.get("users", ":id", "logs", use: getRawLogs)
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
        let context = try authenticatedContext(for: req)
        return try await directoryClient.employer(id: context.id)
    }

    private func getLogs(req: Request) async throws -> Logs {
        let context = try authenticatedContext(for: req)
        let request = try req.content.decode(GetLogsRequest.self)
        let targetID = request.id ?? context.id

        guard targetID == context.id || context.isAdmin else {
            throw Abort(.forbidden, reason: "No access to requested logs")
        }

        let logs = try await logs(for: targetID, after: request.afterDate, on: req.db)
        return Logs(logs: logs)
    }

    private func getStatistic(req: Request) async throws -> Statistic {
        let context = try authenticatedContext(for: req)
        let logs = try await logs(for: context.id, after: nil, on: req.db)
        return Statistic(averageTime: StatisticCalculator(enters: logs).averageTime)
    }

    private func getAll(req: Request) async throws -> Employers {
        let context = try authenticatedContext(for: req)
        guard context.isAdmin else {
            throw Abort(.forbidden, reason: "Admin token required")
        }

        let employers = try await directoryClient.employers()
        let statisticsByEmployer = try await allStatistics(on: req.db)

        let result = employers.compactMap { employer -> EmployerWithStatistic? in
            guard let employerID = employer.id else {
                return nil
            }

            let averageTime = statisticsByEmployer[employerID] ?? 0
            return EmployerWithStatistic(
                employer: employer,
                statistic: Statistic(averageTime: averageTime)
            )
        }

        return Employers(employers: result)
    }

    private func openDoor(req: Request) async throws -> OpeningResult {
        let context = try authenticatedContext(for: req)
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

    private func getRawLogs(req: Request) async throws -> Logs {
        let context = try authenticatedContext(for: req)
        let id = try req.parameters.require("id", as: UUID.self)
        guard context.id == id || context.isAdmin else {
            throw Abort(.forbidden, reason: "No access to requested logs")
        }
        return Logs(logs: try await logs(for: id, after: nil, on: req.db))
    }
}

private extension AccessController {
    func authenticatedContext(for req: Request) throws -> AuthenticatedUserContext {
        do {
            return try AuthenticatedUserContext(headers: req.headers)
        } catch {
            throw Abort(.unauthorized, reason: "Missing trusted user context")
        }
    }

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

    func allStatistics(on database: Database) async throws -> [UUID: Double] {
        if let sqlDatabase = database as? any SQLDatabase {
            do {
                return try await queryStatistics(on: sqlDatabase)
            } catch {
                database.logger.warning("Falling back to in-memory access statistics aggregation: \(error)")
            }
        }

        let enters = try await AccessEnter.query(on: database)
            .sort(\.$employerID, .ascending)
            .sort(\.$time, .ascending)
            .all()

        return statisticsAggregator.averageTimes(for: enters)
    }

    func queryStatistics(on database: any SQLDatabase) async throws -> [UUID: Double] {
        let rows = try await database.raw(
            """
            WITH ordered_events AS (
                SELECT
                    employer_id,
                    time,
                    is_on,
                    LAG(time) OVER (PARTITION BY employer_id ORDER BY time) AS previous_time,
                    LAG(is_on) OVER (PARTITION BY employer_id ORDER BY time) AS previous_is_on
                FROM access_enters
            ),
            daily_work AS (
                SELECT
                    employer_id,
                    DATE(previous_time) AS work_day,
                    SUM(TIMESTAMPDIFF(SECOND, previous_time, time)) / 3600.0 AS worked_hours
                FROM ordered_events
                WHERE is_on = 0
                  AND previous_is_on = 1
                GROUP BY employer_id, DATE(previous_time)
            ),
            entered_days AS (
                SELECT
                    employer_id,
                    DATE(time) AS work_day
                FROM access_enters
                WHERE is_on = 1
                GROUP BY employer_id, DATE(time)
            )
            SELECT
                BIN_TO_UUID(entered_days.employer_id) AS employerID,
                COALESCE(SUM(COALESCE(daily_work.worked_hours, 0)) / NULLIF(COUNT(*), 0), 0) AS averageTime
            FROM entered_days
            LEFT JOIN daily_work
                ON daily_work.employer_id = entered_days.employer_id
               AND daily_work.work_day = entered_days.work_day
            GROUP BY entered_days.employer_id
            """
        ).all(decoding: EmployerAverageTimeRow.self)

        var statisticsByEmployer = [UUID: Double]()
        statisticsByEmployer.reserveCapacity(rows.count)

        for row in rows {
            guard let employerID = UUID(uuidString: row.employerID) else {
                throw Abort(.internalServerError, reason: "Invalid employer ID in aggregated access statistics result")
            }

            statisticsByEmployer[employerID] = row.averageTime
        }

        return statisticsByEmployer
    }
}

private struct EmployerAverageTimeRow: Decodable {
    let employerID: String
    let averageTime: Double
}
