import Fluent

struct AddAttendanceAnalysisResultRiskFields: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(AttendanceAnalysisResult.schema)
            .field("risk_score", .double)
            .field("risk_zone", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(AttendanceAnalysisResult.schema)
            .deleteField("risk_score")
            .deleteField("risk_zone")
            .update()
    }
}
