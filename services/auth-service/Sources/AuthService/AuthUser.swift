import Fluent
import Vapor

final class AuthUser: Model, Content {
    static let schema = "auth_users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "email")
    var email: String

    @Field(key: "password")
    var password: String

    @Field(key: "is_admin")
    var isAdmin: Bool

    init() { }

    init(id: UUID, email: String, password: String, isAdmin: Bool) {
        self.id = id
        self.email = email
        self.password = password
        self.isAdmin = isAdmin
    }
}
