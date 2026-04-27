import Fluent
import Foundation

final class ExternalContextCache: Model {
    static let schema = "external_context_cache"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "factor")
    var factor: String

    @Field(key: "day")
    var day: Date

    @Field(key: "city")
    var city: String

    @Field(key: "source_name")
    var sourceName: String

    @Field(key: "source_url")
    var sourceURL: String

    @Field(key: "fetch_status")
    var fetchStatus: String

    @OptionalField(key: "raw_payload_json")
    var rawPayloadJson: String?

    @OptionalField(key: "parsed_payload_json")
    var parsedPayloadJson: String?

    @OptionalField(key: "resolved_value_json")
    var resolvedValueJson: String?

    @OptionalField(key: "source_updated_at")
    var sourceUpdatedAt: Date?

    @OptionalField(key: "fetched_at")
    var fetchedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() { }

    init(
        id: UUID? = nil,
        factor: String,
        day: Date,
        city: String,
        sourceName: String,
        sourceURL: String,
        fetchStatus: String,
        rawPayloadJson: String? = nil,
        parsedPayloadJson: String? = nil,
        resolvedValueJson: String? = nil,
        sourceUpdatedAt: Date? = nil,
        fetchedAt: Date? = nil
    ) {
        self.id = id
        self.factor = factor
        self.day = day
        self.city = city
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.fetchStatus = fetchStatus
        self.rawPayloadJson = rawPayloadJson
        self.parsedPayloadJson = parsedPayloadJson
        self.resolvedValueJson = resolvedValueJson
        self.sourceUpdatedAt = sourceUpdatedAt
        self.fetchedAt = fetchedAt
    }
}
