import Fluent

struct CreateExternalContextCache: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(ExternalContextCache.schema)
            .id()
            .field("factor", .string, .required)
            .field("day", .datetime, .required)
            .field("city", .string, .required)
            .field("source_name", .string, .required)
            .field("source_url", .string, .required)
            .field("fetch_status", .string, .required)
            .field("raw_payload_json", .custom("TEXT"))
            .field("parsed_payload_json", .custom("TEXT"))
            .field("resolved_value_json", .custom("TEXT"))
            .field("source_updated_at", .datetime)
            .field("fetched_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "factor", "day", "city")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(ExternalContextCache.schema).delete()
    }
}
