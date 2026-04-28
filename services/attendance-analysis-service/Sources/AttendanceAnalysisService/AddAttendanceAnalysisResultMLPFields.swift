import Fluent

struct AddAttendanceAnalysisResultMLPFields: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(AttendanceAnalysisResult.schema)
            .field("eta_nn", .double)
            .field("mlp_model_version", .string)
            .field("mlp_status", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(AttendanceAnalysisResult.schema)
            .deleteField("eta_nn")
            .deleteField("mlp_model_version")
            .deleteField("mlp_status")
            .update()
    }
}
