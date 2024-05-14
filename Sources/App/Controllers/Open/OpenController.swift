//
//  OpenController.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Vapor

struct OpenController: RouteCollection {
    
    private let db: DBManager
    
    private let controllerPath: PathComponent = "open"
    
    init(db: DBManager) {
        self.db = db
    }
    
    func boot(routes: any RoutesBuilder) throws {
        let openRoutes = routes.grouped(controllerPath)
        let protected = openRoutes
            .grouped(AuthTokenAuthenticator(db: db))
            .grouped(Employer.guardMiddleware())
        protected.get(OpenRoutes.open.route, use: open)
    }
    
    @Sendable func open(req: Request) async throws -> OpeningResult {
        let employer = try req.auth.require(Employer.self)
        guard let id = employer.id else { throw HTTPClientError.invalidHeaderFieldNames(["id"]) }
        let isSuccess = try await ArduinoManager.shared.open()
        if isSuccess {
            try await db.addEnter(for: id)
        }
        return OpeningResult(isSuccess: isSuccess)
    }
    
}
