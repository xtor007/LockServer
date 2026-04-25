import Fluent
import Vapor

final class DirectoryEmployer: Model, Content {
    static let schema = "directory_employers"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String?

    @Field(key: "surname")
    var surname: String?

    @Field(key: "department")
    var department: String?

    @Field(key: "email")
    var email: String?

    @Field(key: "is_admin")
    var isAdmin: Bool

    @Children(for: \.$employer)
    var cards: [DirectoryCard]

    @Children(for: \.$employer)
    var fingers: [DirectoryFinger]

    init() { }

    init(id: UUID, name: String?, surname: String?, department: String?, email: String?, isAdmin: Bool) {
        self.id = id
        self.name = name
        self.surname = surname
        self.department = department
        self.email = email
        self.isAdmin = isAdmin
    }
}
