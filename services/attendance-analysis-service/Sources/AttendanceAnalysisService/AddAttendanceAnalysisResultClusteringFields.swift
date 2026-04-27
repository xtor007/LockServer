import Fluent

struct AddAttendanceAnalysisResultClusteringFields: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(AttendanceAnalysisResult.schema)
            .field("cluster_name", .string)
            .field("cluster_score", .double)
            .field("cluster_weight", .double)
            .field("cluster_model_version", .int)
            .field("cluster_distance", .double)
            .field("clustering_status", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(AttendanceAnalysisResult.schema)
            .deleteField("cluster_name")
            .deleteField("cluster_score")
            .deleteField("cluster_weight")
            .deleteField("cluster_model_version")
            .deleteField("cluster_distance")
            .deleteField("clustering_status")
            .update()
    }
}
