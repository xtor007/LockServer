import Foundation
import JWT
import Vapor

public struct AuthTokenPayload: JWTPayload {
    public var subject: SubjectClaim
    public var expiration: ExpirationClaim

    public init(subject: SubjectClaim, expiration: ExpirationClaim) {
        self.subject = subject
        self.expiration = expiration
    }

    public func verify(using signer: JWTSigner) throws {
        try expiration.verifyNotExpired()
    }
}

public struct RefreshTokenPayload: JWTPayload {
    public var subject: SubjectClaim
    public var expiration: ExpirationClaim

    public init(login: String) {
        expiration = .init(value: .distantFuture)
        subject = .init(value: "\(RefreshTokenPayloadConstants.prefix)\(login)")
    }

    public var login: String {
        subject.value.replacingOccurrences(of: RefreshTokenPayloadConstants.prefix, with: "")
    }

    public func verify(using signer: JWTSigner) throws {
        try expiration.verifyNotExpired()
    }
}

public enum RefreshTokenPayloadConstants {
    public static let prefix = "refresh-"
}

public struct AuthenticatedUserContext: Content, Equatable {
    public let id: UUID
    public let email: String
    public let isAdmin: Bool

    public init(id: UUID, email: String, isAdmin: Bool) {
        self.id = id
        self.email = email
        self.isAdmin = isAdmin
    }
}
