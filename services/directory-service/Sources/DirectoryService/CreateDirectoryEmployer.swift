import Fluent

struct CreateDirectoryEmployer: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(DirectoryEmployer.schema)
            .id()
            .field("name", .string)
            .field("surname", .string)
            .field("department", .string)
            .field("email", .string, .required)
            .field("is_admin", .bool, .required)
            .unique(on: "email")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(DirectoryEmployer.schema).delete()
    }
}
