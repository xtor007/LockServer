import Fluent
import Vapor

final class AttendanceAnalysisResult: Model, Content {
    static let schema = "attendance_analysis_results"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userId: UUID

    @Field(key: "day")
    var day: Date

    @Field(key: "status")
    var status: String

    @OptionalField(key: "observation_id")
    var observationId: UUID?

    @Field(key: "details_json")
    var detailsJson: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() { }

    init(id: UUID? = nil, userId: UUID, day: Date, status: String, observationId: UUID?, detailsJson: String) {
        self.id = id ?? UUID()
        self.userId = userId
        self.day = day
        self.status = status
        self.observationId = observationId
        self.detailsJson = detailsJson
    }
}
