import Foundation
import Vapor

public struct AuthUserUpsertRequest: Content, Equatable {
    public let id: UUID
    public let email: String
    public let password: String
    public let isAdmin: Bool
    public let sendWelcomeEmail: Bool

    public init(id: UUID, email: String, password: String, isAdmin: Bool, sendWelcomeEmail: Bool) {
        self.id = id
        self.email = email
        self.password = password
        self.isAdmin = isAdmin
        self.sendWelcomeEmail = sendWelcomeEmail
    }
}

public struct DirectoryEmployerUpsertRequest: Content, Equatable {
    public let employer: EmployerModel

    public init(employer: EmployerModel) {
        self.employer = employer
    }
}

public struct DirectoryEmployersResponse: Content, Equatable {
    public let employers: [EmployerModel]

    public init(employers: [EmployerModel]) {
        self.employers = employers
    }
}

public struct CredentialLookupResponse: Content, Equatable {
    public let employerID: UUID?

    public init(employerID: UUID?) {
        self.employerID = employerID
    }
}
