import Fluent

struct CreateAccessEnter: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(AccessEnter.schema)
            .id()
            .field("employer_id", .uuid, .required)
            .field("time", .datetime, .required)
            .field("is_on", .bool, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(AccessEnter.schema).delete()
    }
}
