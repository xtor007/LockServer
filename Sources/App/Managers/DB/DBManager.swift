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
}

protocol CardDBModel {
    var code: String { get }
    var employerID: UUID? { get }
}

protocol EmployerDBModel {
}
