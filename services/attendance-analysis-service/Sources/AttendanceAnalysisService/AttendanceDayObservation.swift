import Fluent
import Vapor

final class AttendanceDayObservation: Model, Content {
    static let schema = "attendance_day_observations"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userId: UUID

    @Field(key: "day")
    var day: Date

    @OptionalField(key: "first_entry_time")
    var firstEntryTime: Date?

    @Field(key: "worked_minutes")
    var workedMinutes: Int

    @Field(key: "break_minutes")
    var breakMinutes: Int

    @Field(key: "sessions_count")
    var sessionsCount: Int

    @Field(key: "is_technical_anomaly")
    var isTechnicalAnomaly: Bool

    @OptionalField(key: "anomaly_reason")
    var anomalyReason: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() { }

    init(
        id: UUID? = nil,
        userId: UUID,
        day: Date,
        firstEntryTime: Date?,
        workedMinutes: Int,
        breakMinutes: Int,
        sessionsCount: Int,
        isTechnicalAnomaly: Bool,
        anomalyReason: String?
    ) {
        self.id = id ?? UUID()
        self.userId = userId
        self.day = day
        self.firstEntryTime = firstEntryTime
        self.workedMinutes = workedMinutes
        self.breakMinutes = breakMinutes
        self.sessionsCount = sessionsCount
        self.isTechnicalAnomaly = isTechnicalAnomaly
        self.anomalyReason = anomalyReason
    }
}
