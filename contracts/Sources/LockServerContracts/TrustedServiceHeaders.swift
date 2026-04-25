import Foundation
import Vapor

public enum TrustedServiceHeaders {
    public static let userID = "X-Lock-User-Id"
    public static let userEmail = "X-Lock-User-Email"
    public static let userIsAdmin = "X-Lock-User-Is-Admin"
}

public enum TrustedUserContextError: Error {
    case missingHeader(String)
    case invalidUUID(String)
}

public extension AuthenticatedUserContext {
    init(headers: HTTPHeaders) throws {
        guard let idValue = headers.first(name: TrustedServiceHeaders.userID) else {
            throw TrustedUserContextError.missingHeader(TrustedServiceHeaders.userID)
        }
        guard let id = UUID(uuidString: idValue) else {
            throw TrustedUserContextError.invalidUUID(idValue)
        }
        guard let email = headers.first(name: TrustedServiceHeaders.userEmail) else {
            throw TrustedUserContextError.missingHeader(TrustedServiceHeaders.userEmail)
        }
        guard let isAdminValue = headers.first(name: TrustedServiceHeaders.userIsAdmin) else {
            throw TrustedUserContextError.missingHeader(TrustedServiceHeaders.userIsAdmin)
        }

        self.init(id: id, email: email, isAdmin: isAdminValue == "true")
    }
}

public extension HTTPHeaders {
    mutating func addAuthenticatedUserContext(_ context: AuthenticatedUserContext) {
        replaceOrAdd(name: TrustedServiceHeaders.userID, value: context.id.uuidString)
        replaceOrAdd(name: TrustedServiceHeaders.userEmail, value: context.email)
        replaceOrAdd(name: TrustedServiceHeaders.userIsAdmin, value: context.isAdmin ? "true" : "false")
    }
}
