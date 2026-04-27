import Fluent

struct CreateAttendanceClusteringModelRecord: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(AttendanceClusteringModelRecord.schema)
            .id()
            .field("model_version", .int, .required)
            .field("normalization_json", .custom("TEXT"), .required)
            .field("centroids_json", .custom("TEXT"), .required)
            .field("trust_radii_json", .custom("TEXT"), .required)
            .field("cluster_definitions_json", .custom("TEXT"), .required)
            .field("created_at", .datetime)
            .unique(on: "model_version")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(AttendanceClusteringModelRecord.schema).delete()
    }
}
