import Fluent
import Vapor

final class DirectoryFinger: Model, Content {
    static let schema = "directory_fingers"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "code")
    var code: Int

    @Parent(key: "employer_id")
    var employer: DirectoryEmployer

    init() { }

    init(code: Int, employerID: UUID) {
        self.id = UUID()
        self.code = code
        self.$employer.id = employerID
    }
}
