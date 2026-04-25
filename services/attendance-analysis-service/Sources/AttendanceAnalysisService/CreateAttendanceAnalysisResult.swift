import Fluent

struct CreateAttendanceAnalysisResult: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(AttendanceAnalysisResult.schema)
            .id()
            .field("user_id", .uuid, .required)
            .field("day", .datetime, .required)
            .field("status", .string, .required)
            .field("observation_id", .uuid)
            .field("details_json", .custom("TEXT"), .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "user_id", "day")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(AttendanceAnalysisResult.schema).delete()
    }
}
