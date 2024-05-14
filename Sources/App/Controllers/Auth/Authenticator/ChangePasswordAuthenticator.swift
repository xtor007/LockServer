//
//  ChangePasswordAuthenticator.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Vapor

struct ChangePasswordAuthenticator: AsyncBasicAuthenticator {
    
    let db: DBManager
    
    func authenticate( basic: BasicAuthorization, for request: Request) async throws {
        let waitedEmail = ChangePasswordManager.shared.email(for: basic.password)
        guard waitedEmail == basic.username else { throw ChangePasswordError.failedCode }
        let employer = try await db.getUser(for: basic.username)
        request.auth.login(employer)
    }
    
}

enum ChangePasswordError: Error {
    case failedCode
}
