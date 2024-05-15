//
//  CommantController.swift
//
//
//  Created by Anatoliy Khramchenko on 15.05.2024.
//

import Vapor

struct CommantController: RouteCollection {
    
    private let db: DBManager
    private let mail: MailManager
    
    private let controllerPath: PathComponent = "command"
    
    private let queryIdParameterName = "id"
    
    init(db: DBManager, mail: MailManager) {
        self.db = db
        self.mail = mail
    }
    
    func boot(routes: any RoutesBuilder) throws {
        let authRoutes = routes.grouped(controllerPath)
        let protected = authRoutes
            .grouped(AuthTokenAuthenticator(db: db))
            .grouped(Employer.guardMiddleware())
        protected.get(CommandRoutes.delete.route, use: delete)
        protected.post(CommandRoutes.add.route, use: add)
    }
    
    @Sendable func delete(req: Request) async throws -> ValidServerResponse {
        let employer = try req.auth.require(Employer.self)
        guard employer.isAdmin else { throw CommandError.noAccess }
        let idString = try req.query.get(String.self, at: queryIdParameterName)
        guard let id = UUID(idString) else {
            throw CommandError.failedId
        }
        let deletingEmployer = try await db.getUser(by: id)
        guard !deletingEmployer.isAdmin else { throw CommandError.noAccess }
        try await db.removeUser(with: id)
        return ValidServerResponse(isValid: true)
    }
    
    @Sendable func add(req: Request) async throws -> ValidServerResponse {
        let employer = try req.auth.require(Employer.self)
        guard employer.isAdmin else { throw CommandError.noAccess }
        let newEmployer = try req.content.decode(EmployerModel.self)
        let password = generatePassword()
        try await db.addUser(newEmployer, password: password)
        Task {
            guard let email = newEmployer.email else {
                return
            }
            mail.sendPassword(password, to: email)
        }
        return ValidServerResponse(isValid: true)
    }
    
    private func generatePassword() -> String {
        let letters = "0123456789abcdefghijklmnopqrstuvwxyz"
        var password = ""
        for _ in 0..<8 {
            password.append(letters.randomElement()!)
        }
        return password
    }
}

enum CommandError: Error {
    case noAccess, failedId
}
