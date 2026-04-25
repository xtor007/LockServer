import Fluent

struct CreateDirectoryFinger: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(DirectoryFinger.schema)
            .id()
            .field("code", .int, .required)
            .field("employer_id", .uuid, .required, .references(DirectoryEmployer.schema, .id, onDelete: .cascade))
            .unique(on: "code")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(DirectoryFinger.schema).delete()
    }
}
