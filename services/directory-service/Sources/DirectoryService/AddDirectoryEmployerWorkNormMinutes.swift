import Fluent

struct AddDirectoryEmployerWorkNormMinutes: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(DirectoryEmployer.schema)
            .field("work_norm_minutes", .int)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(DirectoryEmployer.schema)
            .deleteField("work_norm_minutes")
            .update()
    }
}
