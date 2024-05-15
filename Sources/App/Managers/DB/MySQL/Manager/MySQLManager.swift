//
//  MySQLManager.swift
//
//
//  Created by Anatoliy Khramchenko on 13.05.2024.
//

import Vapor
import Fluent
import FluentMySQLDriver

class MySQLManager: DBManager {
    
    static let shared = MySQLManager()
    
    private var db: Database?
    
    private init() {}
    
    func setup(_ app: Application) {
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.certificateVerification = .none
        app.databases.use(.mysql(
            hostname: MySQLConstants.host,
            username: MySQLConstants.user,
            password: MySQLConstants.password,
            database: MySQLConstants.scheme,
            tlsConfiguration: tls
        ), as: .mysql)
        app.migrations.add(CreateEmployer())
        app.migrations.add(CreateCard())
        app.migrations.add(CreateEnter())
        do {
            try app.autoMigrate().wait()
        } catch {
            print(error)
        }
        db = app.db
    }
    
}

// MARK: - Methods

extension MySQLManager {
    
    func getCards(forHash hash: Int) async throws -> [any CardDBModel] {
        guard let db else { throw MySQLError.noDB }
        return try await Card.query(on: db).filter(\.$hash == hash).with(\.$employer).all()
    }
    
    func addEnter(for id: UUID) async throws {
        guard let db else { throw MySQLError.noDB }
        let lastEnter = try await Enter.query(on: db)
            .filter(\.$employer.$id == id)
            .sort(\.$time, .descending)
            .first()
        let isOn = !(lastEnter?.isOn ?? false)
        let newEnter = Enter(employerID: id, isOn: isOn)
        try await newEnter.create(on: db)
    }
    
    func getUser(for email: String) async throws -> any EmployerDBModel {
        guard let db else { throw MySQLError.noDB }
        guard let employer = try await Employer.query(on: db)
            .filter(\.$email == email)
            .first() else {
            throw MySQLError.userNotFound
        }
        return employer
    }
    
    func getUser(by id: UUID) async throws -> any EmployerDBModel {
        guard let db else { throw MySQLError.noDB }
        guard let employer = try await Employer.query(on: db)
            .filter(\.$id == id)
            .first() else {
            throw MySQLError.userNotFound
        }
        return employer
    }
    
    func updatePassword(for userID: UUID, newPassword: String) async throws {
        guard let db else { throw MySQLError.noDB }
        guard let employer = try await Employer.query(on: db).filter(\.$id == userID).first() else {
            throw MySQLError.userNotFound
        }
        employer.password = newPassword
        try await employer.update(on: db)
    }
    
    func getLogs(for userId: UUID, after date: Date?) async throws -> [any EnterDBModel] {
        guard let db else { throw MySQLError.noDB }
        return try await Enter.query(on: db)
            .with(\.$employer)
            .filter(\.$employer.$id == userId)
            .filter(\.$time > date ?? .distantPast)
            .all()
    }
    
    func getAllEmployers() async throws -> [any EmployerDBModel] {
        guard let db else { throw MySQLError.noDB }
        return try await Employer.query(on: db).all()
    }
    
    func removeUser(with id: UUID) async throws {
        guard let db else { throw MySQLError.noDB }
        guard let employer = try await getUser(by: id) as? Employer else {
            throw MySQLError.userNotFound
        }
        try await db.query(Enter.self).with(\.$employer).filter(\.$employer.$id == id).delete()
        try await db.query(Card.self).with(\.$employer).filter(\.$employer.$id == id).delete()
        try await employer.delete(on: db)
    }
    
    func addUser(_ user: EmployerModel, password: String) async throws {
        guard let db else { throw MySQLError.noDB }
        let employer = Employer(
            name: user.name,
            surname: user.surname,
            department: user.department,
            email: user.email,
            password: password,
            isAdmin: user.isAdmin
        )
        try await employer.create(on: db)
    }
    
}

// MARK: - Errors

enum MySQLError: Error {
    case noDB, failedAuth, userNotFound
}
