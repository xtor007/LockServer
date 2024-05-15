//
//  GetLogsRequest.swift
//
//
//  Created by Anatoliy Khramchenko on 15.05.2024.
//

import Vapor

struct GetLogsRequest: Content {
    let valid: Bool
    let id: UUID?
    let afterDate: Date?
}
