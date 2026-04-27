import Foundation
import Vapor

struct AlertsInUAAirAlertsProviderClient: AirAlertsProvider {
    private let client: Client
    private let apiToken: String
    private let configuration: AlertsInUAAirAlertsConfiguration
    private let decoder: JSONDecoder

    var city: String {
        configuration.city
    }

    var sourceName: String {
        configuration.sourceName
    }

    var sourceURL: String {
        configuration.sourceURL
    }

    init(client: Client, apiToken: String, configuration: AlertsInUAAirAlertsConfiguration) {
        self.client = client
        self.apiToken = apiToken
        self.configuration = configuration

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            for formatter in Self.makeDateFormatters() {
                if let date = formatter.date(from: value) {
                    return date
                }
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported alerts.in.ua date")
        }
        self.decoder = decoder
    }

    func supports(day: ExternalContextDay) -> Bool {
        let today = ExternalContextDay(date: Date())
        let maxHistoryWindow = TimeInterval(31 * 24 * 60 * 60)
        let oldestSupportedDay = today.startOfDay.addingTimeInterval(-maxHistoryWindow)
        return day.startOfDay <= today.startOfDay && day.startOfDay >= oldestSupportedDay
    }

    func fetchAirAlerts(for day: ExternalContextDay) async throws -> AirAlertsProviderFetchOutput {
        try validate(day: day)

        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .authorization, value: "Bearer \(apiToken)")

        let response = try await client.send(.GET, headers: headers, to: URI(string: configuration.sourceURL))
        guard response.status == .ok, let body = response.body else {
            let reason = response.body.flatMap {
                $0.getString(at: $0.readerIndex, length: $0.readableBytes)
            } ?? "alerts.in.ua history request failed"
            throw Abort(.badGateway, reason: reason)
        }

        let historyResponse = try decodeHistoryResponse(from: Data(buffer: body))
        let rawPayload = makeRawPayload(from: historyResponse, for: day)

        return AirAlertsProviderFetchOutput(
            rawPayload: rawPayload,
            sourceName: sourceName,
            sourceURL: sourceURL
        )
    }
}

extension AlertsInUAAirAlertsProviderClient {
    struct HistoryResponse: Decodable, Equatable {
        let alerts: [HistoryAlert]
    }

    struct HistoryAlert: Decodable, Equatable {
        let id: Int64
        let locationTitle: String
        let locationType: String?
        let startedAt: Date
        let finishedAt: Date?
        let updatedAt: Date?
        let alertType: String
        let locationUID: String?
        let notes: String?
        let calculated: Bool?

        enum CodingKeys: String, CodingKey {
            case id
            case locationTitle = "location_title"
            case locationType = "location_type"
            case startedAt = "started_at"
            case finishedAt = "finished_at"
            case updatedAt = "updated_at"
            case alertType = "alert_type"
            case locationUID = "location_uid"
            case notes
            case calculated
        }
    }

    func decodeHistoryResponse(from data: Data) throws -> HistoryResponse {
        do {
            return try decoder.decode(HistoryResponse.self, from: data)
        } catch {
            throw Abort(.badGateway, reason: "alerts.in.ua history response is invalid")
        }
    }

    func makeRawPayload(from response: HistoryResponse, for day: ExternalContextDay) -> AirAlertsRawPayload {
        let dayEnd = day.startOfDay.addingTimeInterval(24 * 60 * 60)
        let alerts = response.alerts
            .filter { alert in
                let effectiveEnd = alert.finishedAt ?? dayEnd
                return alert.startedAt < dayEnd && effectiveEnd > day.startOfDay
            }
            .map { alert in
                AirAlertsRawAlert(
                    id: String(alert.id),
                    locationTitle: alert.locationTitle,
                    locationUID: alert.locationUID,
                    alertType: alert.alertType,
                    startedAt: alert.startedAt,
                    finishedAt: alert.finishedAt,
                    updatedAt: alert.updatedAt,
                    notes: alert.notes,
                    calculated: alert.calculated
                )
            }

        return AirAlertsRawPayload(
            day: day.stringValue,
            city: configuration.city,
            sourceKind: "\(configuration.sourceName):\(configuration.historyPeriod)",
            sourceUpdatedAt: alerts.compactMap { $0.updatedAt ?? $0.finishedAt }.max(),
            alerts: alerts
        )
    }
}

private extension AlertsInUAAirAlertsProviderClient {
}

extension AlertsInUAAirAlertsProviderClient {
    func validate(day: ExternalContextDay) throws {
        let today = ExternalContextDay(date: Date())
        guard day.startOfDay <= today.startOfDay else {
            throw Abort(.badRequest, reason: "Air alerts are available only for current or past days")
        }

        guard supports(day: day) else {
            throw Abort(.badRequest, reason: "alerts.in.ua history currently supports only recent dates within month_ago")
        }
    }
}

private extension AlertsInUAAirAlertsProviderClient {
    static func makeDateFormatters() -> [ISO8601DateFormatter] {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let withoutFractionalSeconds = ISO8601DateFormatter()
        withoutFractionalSeconds.formatOptions = [.withInternetDateTime]

        return [withFractionalSeconds, withoutFractionalSeconds]
    }
}
