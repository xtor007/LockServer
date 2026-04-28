import Fluent

struct CreateAttendanceMLPFeedbackSample: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(AttendanceMLPFeedbackSample.schema)
            .id()
            .field("user_id", .uuid, .required)
            .field("day", .datetime, .required)
            .field("z_s", .double, .required)
            .field("z_t", .double, .required)
            .field("f", .double, .required)
            .field("air_alert_minutes", .int, .required)
            .field("traffic_score", .double, .required)
            .field("power_score", .double, .required)
            .field("weather_score", .double, .required)
            .field("eta_nn_target", .double, .required)
            .field("source_model_version", .string, .required)
            .field("consumed_model_version", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(AttendanceMLPFeedbackSample.schema).delete()
    }
}
