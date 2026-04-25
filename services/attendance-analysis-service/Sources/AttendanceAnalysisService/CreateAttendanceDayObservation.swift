import Fluent

struct CreateAttendanceDayObservation: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(AttendanceDayObservation.schema)
            .id()
            .field("user_id", .uuid, .required)
            .field("day", .datetime, .required)
            .field("first_entry_time", .datetime)
            .field("worked_minutes", .int, .required)
            .field("break_minutes", .int, .required)
            .field("sessions_count", .int, .required)
            .field("is_technical_anomaly", .bool, .required)
            .field("anomaly_reason", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "user_id", "day")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(AttendanceDayObservation.schema).delete()
    }
}
