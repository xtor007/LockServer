import Foundation

public struct VersionedDomainEvent<Payload: Encodable>: Encodable {
    public let version: Int
    public let name: String
    public let source: String
    public let occurredAt: Date
    public let payload: Payload

    public init(version: Int = 1, name: String, source: String, occurredAt: Date = .now, payload: Payload) {
        self.version = version
        self.name = name
        self.source = source
        self.occurredAt = occurredAt
        self.payload = payload
    }
}
