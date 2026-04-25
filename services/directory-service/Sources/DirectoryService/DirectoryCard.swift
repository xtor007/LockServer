import Fluent
import Vapor

final class DirectoryCard: Model, Content {
    static let schema = "directory_cards"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "hash")
    var hash: Int

    @Field(key: "code")
    var code: String

    @Parent(key: "employer_id")
    var employer: DirectoryEmployer

    init() { }

    init(hash: Int, code: String, employerID: UUID) {
        self.id = UUID()
        self.hash = hash
        self.code = code
        self.$employer.id = employerID
    }
}
