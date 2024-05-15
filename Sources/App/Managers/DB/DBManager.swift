//
//  DBManager.swift
//
//
//  Created by Anatoliy Khramchenko on 13.05.2024.
//

import Vapor

protocol DBManager: AnyObject {
    func setup(_ app: Application)
    func getCards(forHash hash: Int) async throws -> [CardDBModel]
    func addEnter(for id: UUID) async throws
    func getUser(for email: String) async throws -> any EmployerDBModel
    func getUser(by id: UUID) async throws -> any EmployerDBModel
    func updatePassword(for userID: UUID, newPassword: String) async throws
    func getLogs(for userId: UUID, after date: Date?) async throws -> [EnterDBModel]
    func getAllEmployers() async throws -> [EmployerDBModel]
    func removeUser(with id: UUID) async throws
    func addUser(_ user: EmployerModel, password: String) async throws
}

// MARK: - DB Models interfaces

protocol CardDBModel {
    var code: String { get }
    var employerID: UUID? { get }
}

protocol EnterDBModel {
    var time: Date { get }
    var isOn: Bool { get }
    
    func makeModel() -> EnterModel
}

protocol EmployerDBModel: Authenticatable, AnyObject {
    var id: UUID? { get }
    var name: String? { get }
    var surname: String? { get }
    var department: String? { get }
    var email: String? { get }
    var password: String? { get }
    var isAdmin: Bool { get }
    
    func makeModel() -> EmployerModel
}

// MARK: - Methods

extension EmployerDBModel {
    func makeModel() -> EmployerModel {
        EmployerModel(
            id: id,
            isAdmin: isAdmin,
            name: name,
            surname: surname,
            department: department,
            email: email
        )
    }
}

extension EnterDBModel {
    func makeModel() -> EnterModel {
        EnterModel(isOn: isOn, time: time)
    }
}
