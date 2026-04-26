import Fluent

struct AddAttendanceAnalysisResultCoreSignals: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(AttendanceAnalysisResult.schema)
            .field("history_days_used", .int)
            .field("average_start_minutes", .double)
            .field("stddev_start_minutes", .double)
            .field("stddev_worked_minutes", .double)
            .field("work_norm_minutes", .int)
            .field("z_s", .double)
            .field("z_t", .double)
            .field("f", .double)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(AttendanceAnalysisResult.schema)
            .deleteField("history_days_used")
            .deleteField("average_start_minutes")
            .deleteField("stddev_start_minutes")
            .deleteField("stddev_worked_minutes")
            .deleteField("work_norm_minutes")
            .deleteField("z_s")
            .deleteField("z_t")
            .deleteField("f")
            .update()
    }
}
