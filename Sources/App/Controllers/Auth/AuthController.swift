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
    private let mail: MailManager
    
    private let controllerPath: PathComponent = "auth"
    
    init(db: DBManager, mail: MailManager) {
        self.db = db
        self.mail = mail
    }
    
    func boot(routes: any RoutesBuilder) throws {
        let authRoutes = routes.grouped(controllerPath)
        authRoutes.post(AuthRoutes.sendEmailForChangePassword.route, use: sendEmail)
        
        let basicProtected = authRoutes
            .grouped(EmployerBasicAuthenticator(db: db))
            .grouped(Employer.guardMiddleware())
        basicProtected.get(AuthRoutes.getToken.route, use: getToken)
        
        let refreshTokenProtected = authRoutes
            .grouped(RefreshTokenAuthenticator(db: db))
            .grouped(Employer.guardMiddleware())
        refreshTokenProtected.get(AuthRoutes.refreshToken.route, use: refreshToken)
        
        let changePasswordProtected = authRoutes
            .grouped(ChangePasswordAuthenticator(db: db))
            .grouped(Employer.guardMiddleware())
        changePasswordProtected.post(AuthRoutes.changePassword.route, use: changePassword)
    }
    
    @Sendable func getToken(req: Request) async throws -> AuthTokens {
        let employer = try req.auth.require(Employer.self)
        return try makeTokens(for: employer, with: req)
    }
    
    @Sendable func refreshToken(req: Request) async throws -> AuthTokens {
        let employer = try req.auth.require(Employer.self)
        return try makeTokens(for: employer, with: req)
    }
    
    @Sendable func sendEmail(req: Request) async throws -> ChangePasswordCode {
        let email = try req.content.decode(ChangePasswordEmail.self)
        let code = ChangePasswordManager.shared.makeCode(for: email.email)
        mail.sendCode(code, to: email.email)
        return ChangePasswordCode(code: code)
    }
    
    @Sendable func changePassword(req: Request) async throws -> ValidServerResponse {
        let employer = try req.auth.require(Employer.self)
        guard let id = employer.id else { throw HTTPClientError.invalidHeaderFieldNames(["id"]) }
        let password = try req.content.decode(PasswordContainer.self)
        try await db.updatePassword(for: id, newPassword: password.password)
        return ValidServerResponse(isValid: true)
    }
    
}

// MARK: - Methods

extension AuthController {
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
