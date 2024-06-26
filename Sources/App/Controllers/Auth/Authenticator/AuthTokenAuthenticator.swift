//
//  AuthTokenAuthenticator.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Vapor

struct AuthTokenAuthenticator: AsyncBearerAuthenticator {
    
    let db: DBManager
    
    func authenticate(bearer: Vapor.BearerAuthorization, for request: Vapor.Request) async throws {
        let token = try request.jwt.verify(bearer.token, as: AuthTokenPayload.self)
        guard token.expiration.value > .now else { throw AuthError.tokenFailed }
        let employer = try await db.getUser(for: token.subject.value)
        request.auth.login(employer)
    }
    
}

enum AuthError: Error {
    case tokenFailed
}
