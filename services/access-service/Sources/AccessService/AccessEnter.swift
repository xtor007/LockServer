import Fluent
import Vapor

final class AccessEnter: Model, Content {
    static let schema = "access_enters"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "employer_id")
    var employerID: UUID

    @Field(key: "time")
    var time: Date

    @Field(key: "is_on")
    var isOn: Bool

    init() { }

    init(employerID: UUID, time: Date = .now, isOn: Bool) {
        self.id = UUID()
        self.employerID = employerID
        self.time = time
        self.isOn = isOn
    }
}
