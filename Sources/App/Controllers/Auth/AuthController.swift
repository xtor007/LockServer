//
//  AuthController.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Foundation
import Vapor

struct AuthController: RouteCollection {
    
    private let db: DBManager
    
    private let controllerPath: PathComponent = "auth"
    
    init(db: DBManager) {
        self.db = db
    }
    
    func boot(routes: any RoutesBuilder) throws {
        let authRoutes = routes.grouped(controllerPath)
        
        let basicProtected = authRoutes
            .grouped(EmployerBasicAuthenticator(db: db))
            .grouped(Employer.guardMiddleware())
        basicProtected.get(AuthRoutes.getToken.route, use: getToken)
        
        let refreshTokenProtected = authRoutes
            .grouped(RefreshTokenAuthenticator(db: db))
            .grouped(Employer.guardMiddleware())
        refreshTokenProtected.get(AuthRoutes.refreshToken.route, use: refreshToken)
    }
    
    @Sendable func getToken(req: Request) async throws -> AuthTokens {
        let employer = try req.auth.require(Employer.self)
        return try makeTokens(for: employer, with: req)
    }
    
    @Sendable func refreshToken(req: Request) async throws -> AuthTokens {
        let employer = try req.auth.require(Employer.self)
        return try makeTokens(for: employer, with: req)
    }
    
    private func makeTokens(for employer: EmployerDBModel, with req: Request) throws -> AuthTokens {
        guard let email = employer.email else {
            throw HTTPClientError.invalidHeaderFieldNames(["login"])
        }
        
        let expDate = Date.now + AuthConstants.expTime
        let authTokenPayload = AuthTokenPayload(subject: .init(value: email), expiration: .init(value: expDate))
        let authToken = try req.jwt.sign(authTokenPayload)
        
        let refreshTokenPayload = RefreshTokenPayload(login: email)
        let refreshToken = try req.jwt.sign(refreshTokenPayload)
        
        return AuthTokens(auth: authToken, refresh: refreshToken, expDate: expDate)
    }
    
}
