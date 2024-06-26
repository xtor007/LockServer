//
//  InfoController.swift
//
//
//  Created by Anatoliy Khramchenko on 15.05.2024.
//

import Vapor

struct InfoController: RouteCollection {
    
    private let db: DBManager
    
    private let controllerPath: PathComponent = "info"
    
    init(db: DBManager) {
        self.db = db
    }
    
    func boot(routes: any RoutesBuilder) throws {
        let authRoutes = routes.grouped(controllerPath)
        let protected = authRoutes
            .grouped(AuthTokenAuthenticator(db: db))
            .grouped(Employer.guardMiddleware())
        protected.get(InfoRoutes.getInfo.route, use: getInfo)
        protected.post(InfoRoutes.getLogs.route, use: getLogs)
        protected.get(InfoRoutes.getStatistic.route, use: getStatistic)
        protected.get(InfoRoutes.allUsers.route, use: getAll)
    }
    
    @Sendable func getInfo(req: Request) async throws -> EmployerModel {
        let employer = try req.auth.require(Employer.self)
        return employer.makeModel()
    }
    
    @Sendable func getLogs(req: Request) async throws -> Logs {
        let employer = try req.auth.require(Employer.self)
        let reqData = try req.content.decode(GetLogsRequest.self)
        guard let id = reqData.id ?? employer.id else { // Own id if no id in request
            throw HTTPClientError.invalidHeaderFieldNames(["id"])
        }
        guard id == employer.id || employer.isAdmin else {
            throw GetInfoError.noAccess
        }
        let enters = try await db.getLogs(for: id, after: reqData.afterDate)
        return Logs(logs: enters.map({ $0.makeModel() }))
    }
    
    @Sendable func getStatistic(req: Request) async throws -> Statistic {
        let employer = try req.auth.require(Employer.self)
        guard let id = employer.id else { throw HTTPClientError.invalidHeaderFieldNames(["id"]) }
        let enters = try await db.getLogs(for: id, after: nil)
        let averageTime = StatisticManager(enters: enters).averageTime
        return Statistic(averageTime: averageTime)
    }
    
    @Sendable func getAll(req: Request) async throws -> Employers {
        let employer = try req.auth.require(Employer.self)
        guard employer.isAdmin else { throw GetInfoError.noAccess }
        let employers = try await db.getAllEmployers()
        var employersWithStatistic = [EmployerWithStatistic]()
        for model in employers {
            if let id = model.id {
                let logs = try await db.getLogs(for: id, after: nil)
                let averageTime = StatisticManager(enters: logs).averageTime
                var employer = model.makeModel()
                employer.hasCard = try await db.hasCard(id)
                employer.hasFinger = try await db.hasFinger(id)
                employersWithStatistic.append(EmployerWithStatistic(
                    employer: employer,
                    statistic: Statistic(averageTime: averageTime)
                ))
            }
        }
        return Employers(employers: employersWithStatistic)
    }
    
}

enum GetInfoError: Error {
    case noAccess
}
