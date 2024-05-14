//
//  AuthTokens.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Vapor

struct AuthTokens: Content {
    let auth: String
    let refresh: String
    let expDate: Date
}
