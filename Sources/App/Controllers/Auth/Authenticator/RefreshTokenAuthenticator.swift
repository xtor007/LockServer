//
//  RefreshTokenAuthenticator.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Vapor

struct RefreshTokenAuthenticator: AsyncBearerAuthenticator {
    
    let db: DBManager
    
    func authenticate(bearer: Vapor.BearerAuthorization, for request: Vapor.Request) async throws {
        let token = try request.jwt.verify(bearer.token, as: RefreshTokenPayload.self)
        let employer = try await db.getUser(for: token.login)
        request.auth.login(employer)
    }
    
}

enum TokenAuthError: Error {
    case tokenFailed
}
