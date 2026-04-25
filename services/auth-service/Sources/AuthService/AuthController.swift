import Fluent
import Foundation
import JWT
import LockServerContracts
import Vapor

struct AuthController: RouteCollection {
    private let mailSender: AuthMailSender
    private let codeStore: ResetCodeStore

    init(mailSender: AuthMailSender, codeStore: ResetCodeStore) {
        self.mailSender = mailSender
        self.codeStore = codeStore
    }

    func boot(routes: RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.get("getToken", use: getToken)
        auth.get("refresh", use: refreshToken)
        auth.post("changePasswordEmail", use: sendEmail)
        auth.post("changePassword", use: changePassword)

        let `internal` = routes.grouped("internal", "auth")
        `internal`.get("context", use: context)
        `internal`.post("users", use: upsertUser)
        `internal`.delete("users", ":id", use: deleteUser)
    }

    private func getToken(req: Request) async throws -> AuthTokens {
        guard let basic = req.headers.basicAuthorization else {
            throw Abort(.unauthorized, reason: "Missing basic auth")
        }
        let user = try await user(for: basic.username, on: req.db)
        guard user.password == basic.password else {
            throw Abort(.unauthorized, reason: "Invalid credentials")
        }
        return try tokens(for: user, on: req)
    }

    private func refreshToken(req: Request) async throws -> AuthTokens {
        guard let bearer = req.headers.bearerAuthorization else {
            throw Abort(.unauthorized, reason: "Missing bearer auth")
        }
        let payload = try req.jwt.verify(bearer.token, as: RefreshTokenPayload.self)
        let user = try await user(for: payload.login, on: req.db)
        return try tokens(for: user, on: req)
    }

    private func sendEmail(req: Request) async throws -> ChangePasswordCode {
        let email = try req.content.decode(ChangePasswordEmail.self)
        let code = await codeStore.makeCode(for: email.email)
        mailSender.sendResetCode(code, to: email.email)
        return ChangePasswordCode(code: code)
    }

    private func changePassword(req: Request) async throws -> ValidServerResponse {
        guard let basic = req.headers.basicAuthorization else {
            throw Abort(.unauthorized, reason: "Missing basic auth")
        }
        let matchedEmail = await codeStore.consumeEmail(for: basic.password)
        guard matchedEmail == basic.username else {
            throw Abort(.unauthorized, reason: "Invalid password reset code")
        }

        let password = try req.content.decode(PasswordContainer.self)
        let user = try await user(for: basic.username, on: req.db)
        user.password = password.password
        try await user.update(on: req.db)
        return ValidServerResponse(isValid: true)
    }

    private func context(req: Request) async throws -> AuthenticatedUserContext {
        guard let bearer = req.headers.bearerAuthorization else {
            throw Abort(.unauthorized, reason: "Missing bearer auth")
        }
        let payload = try req.jwt.verify(bearer.token, as: AuthTokenPayload.self)
        let user = try await user(for: payload.subject.value, on: req.db)
        guard let id = user.id else {
            throw Abort(.internalServerError, reason: "Auth user has no id")
        }
        return AuthenticatedUserContext(id: id, email: user.email, isAdmin: user.isAdmin)
    }

    private func upsertUser(req: Request) async throws -> ValidServerResponse {
        let payload = try req.content.decode(AuthUserUpsertRequest.self)

        if let existing = try await AuthUser.find(payload.id, on: req.db) {
            existing.email = payload.email
            existing.password = payload.password
            existing.isAdmin = payload.isAdmin
            try await existing.update(on: req.db)
        } else {
            let user = AuthUser(id: payload.id, email: payload.email, password: payload.password, isAdmin: payload.isAdmin)
            try await user.create(on: req.db)
        }

        if payload.sendWelcomeEmail {
            mailSender.sendWelcomePassword(payload.password, to: payload.email)
        }

        return ValidServerResponse(isValid: true)
    }

    private func deleteUser(req: Request) async throws -> ValidServerResponse {
        let id = try req.parameters.require("id", as: UUID.self)
        guard let user = try await AuthUser.find(id, on: req.db) else {
            return ValidServerResponse(isValid: true)
        }
        guard !user.isAdmin else {
            throw Abort(.forbidden, reason: "Admin user cannot be deleted")
        }
        try await user.delete(on: req.db)
        return ValidServerResponse(isValid: true)
    }
}

private extension AuthController {
    func user(for email: String, on database: Database) async throws -> AuthUser {
        guard let user = try await AuthUser.query(on: database)
            .filter(\.$email == email)
            .first() else {
            throw Abort(.unauthorized, reason: "User not found")
        }
        return user
    }

    func tokens(for user: AuthUser, on req: Request) throws -> AuthTokens {
        let expDate = Date.now.addingTimeInterval(3600)
        let authPayload = AuthTokenPayload(
            subject: .init(value: user.email),
            expiration: .init(value: expDate)
        )
        let refreshPayload = RefreshTokenPayload(login: user.email)
        let authToken = try req.jwt.sign(authPayload)
        let refreshToken = try req.jwt.sign(refreshPayload)
        return AuthTokens(auth: authToken, refresh: refreshToken, expDate: expDate)
    }
}
