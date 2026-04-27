import Foundation

protocol AirAlertsProvider {
    var city: String { get }
    var sourceName: String { get }
    var sourceURL: String { get }

    func supports(day: ExternalContextDay) -> Bool
    func fetchAirAlerts(for day: ExternalContextDay) async throws -> AirAlertsProviderFetchOutput
}

struct AirAlertsRawAlert: Codable, Equatable {
    let id: String
    let locationTitle: String
    let locationUID: String?
    let alertType: String
    let startedAt: Date
    let finishedAt: Date?
    let updatedAt: Date?
    let notes: String?
    let calculated: Bool?
}

struct AirAlertsRawPayload: Codable, Equatable {
    let day: String
    let city: String
    let sourceKind: String
    let sourceUpdatedAt: Date?
    let alerts: [AirAlertsRawAlert]
}

struct AirAlertsProviderFetchOutput: Equatable {
    let rawPayload: AirAlertsRawPayload
    let sourceName: String
    let sourceURL: String
}
