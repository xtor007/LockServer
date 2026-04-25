import Fluent

struct CreateDirectoryCard: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(DirectoryCard.schema)
            .id()
            .field("hash", .int, .required)
            .field("code", .string, .required)
            .field("employer_id", .uuid, .required, .references(DirectoryEmployer.schema, .id, onDelete: .cascade))
            .unique(on: "code")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(DirectoryCard.schema).delete()
    }
}
