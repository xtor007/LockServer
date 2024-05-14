//
//  EmployerBasicAuthenticator.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Vapor

struct EmployerBasicAuthenticator: AsyncBasicAuthenticator {
    
    let db: DBManager
    
    func authenticate( basic: BasicAuthorization, for request: Request) async throws {
        let employer = try await db.getUser(for: basic.username)
        guard employer.password == basic.password else { throw BasicAuthError.failedPassword }
        request.auth.login(employer)
    }
    
}

enum BasicAuthError: Error {
    case failedPassword
}
