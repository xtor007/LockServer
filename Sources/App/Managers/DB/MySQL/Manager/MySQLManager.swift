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
    
    func getUser(for email: String) async throws -> EmployerDBModel {
        guard let db else { throw MySQLError.noDB }
        guard let employer = try await Employer.query(on: db)
            .filter(\.$email == email)
            .first() else {
            throw MySQLError.failedAuth
        }
        return employer
    }
    
}

// MARK: - Errors

enum MySQLError: Error {
    case noDB, failedAuth
}
