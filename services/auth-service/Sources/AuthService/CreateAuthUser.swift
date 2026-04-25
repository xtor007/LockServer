import Fluent

struct CreateAuthUser: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(AuthUser.schema)
            .id()
            .field("email", .string, .required)
            .field("password", .string, .required)
            .field("is_admin", .bool, .required)
            .unique(on: "email")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(AuthUser.schema).delete()
    }
}
