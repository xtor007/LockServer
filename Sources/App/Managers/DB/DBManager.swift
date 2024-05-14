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
    func getUser(for email: String) async throws -> EmployerDBModel
}

protocol CardDBModel {
    var code: String { get }
    var employerID: UUID? { get }
}

protocol EmployerDBModel: Authenticatable, AnyObject {
    var name: String? { get }
    var surname: String? { get }
    var department: String? { get }
    var email: String? { get }
    var password: String? { get }
    var isAdmin: Bool { get }
}
