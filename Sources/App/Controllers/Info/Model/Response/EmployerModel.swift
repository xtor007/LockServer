//
//  EmployerModel.swift
//
//
//  Created by Anatoliy Khramchenko on 15.05.2024.
//

import Vapor

struct EmployerModel: Content {
    let id: UUID?
    let isAdmin: Bool
    let name: String?
    let surname: String?
    let department: String?
    let email: String?
    var hasCard: Bool?
    var hasFinger: Bool?
}
