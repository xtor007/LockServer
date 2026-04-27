import Foundation
import Vapor

struct OpenMeteoWeatherHourSnapshot: Codable, Equatable {
    let time: Date
    let weatherCode: Int?
    let precipitation: Double?
    let temperature2m: Double?
    let visibility: Double?
}

struct OpenMeteoWeatherRawPayload: Codable, Equatable {
    let day: String
    let sourceKind: String
    let queryTimeZone: String
    let latitude: Double
    let longitude: Double
    let sourceUpdatedAt: Date?
    let snapshots: [OpenMeteoWeatherHourSnapshot]
}

struct OpenMeteoWeatherProviderFetchOutput: Equatable {
    let rawPayload: OpenMeteoWeatherRawPayload
    let sourceURL: String
}

struct OpenMeteoWeatherProviderClient {
    private let client: Client
    private let configuration: OpenMeteoWeatherConfiguration
    private let decoder: JSONDecoder

    init(client: Client, configuration: OpenMeteoWeatherConfiguration) {
        self.client = client
        self.configuration = configuration
        self.decoder = JSONDecoder()
    }

    func fetchWeather(for day: ExternalContextDay) async throws -> OpenMeteoWeatherProviderFetchOutput {
        let sourceKind = providerSourceKind(for: day)
        let sourceURL = sourceURL(for: sourceKind)
        let uri = try makeURI(for: day, sourceKind: sourceKind)
        let response = try await client.send(.GET, to: uri)

        guard response.status == .ok, let body = response.body else {
            let reason = response.body.flatMap {
                $0.getString(at: $0.readerIndex, length: $0.readableBytes)
            } ?? "Open-Meteo weather request failed"
            throw Abort(.badGateway, reason: reason)
        }

        let payload = try decoder.decode(ResponsePayload.self, from: Data(buffer: body))
        let snapshots = try makeSnapshots(from: payload)
        let filteredSnapshots = snapshots.filter { snapshot in
            snapshot.time >= day.startOfDay && snapshot.time < day.startOfDay.addingTimeInterval(24 * 60 * 60)
        }
        guard filteredSnapshots.isEmpty == false else {
            throw Abort(.badGateway, reason: "Open-Meteo weather response is missing hourly data")
        }

        let sourceUpdatedAt = latestRelevantSourceUpdate(for: day, snapshots: filteredSnapshots)

        return OpenMeteoWeatherProviderFetchOutput(
            rawPayload: OpenMeteoWeatherRawPayload(
                day: day.stringValue,
                sourceKind: sourceKind.rawValue,
                queryTimeZone: configuration.queryTimeZone,
                latitude: configuration.latitude,
                longitude: configuration.longitude,
                sourceUpdatedAt: sourceUpdatedAt,
                snapshots: filteredSnapshots
            ),
            sourceURL: sourceURL
        )
    }
}

private extension OpenMeteoWeatherProviderClient {
    enum ProviderSourceKind: String, Codable {
        case forecast
        case historical
    }

    struct ResponsePayload: Decodable {
        let hourly: HourlyPayload?
    }

    struct HourlyPayload: Codable {
        let time: [String]
        let weatherCode: [Int?]?
        let precipitation: [Double?]?
        let temperature2m: [Double?]?
        let visibility: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case precipitation
            case temperature2m = "temperature_2m"
            case visibility
        }
    }

    func providerSourceKind(for day: ExternalContextDay) -> ProviderSourceKind {
        if day == ExternalContextDay(date: Date()) {
            return .forecast
        }
        return .historical
    }

    func sourceURL(for sourceKind: ProviderSourceKind) -> String {
        switch sourceKind {
        case .forecast:
            return configuration.forecastSourceURL
        case .historical:
            return configuration.historicalSourceURL
        }
    }

    func makeURI(for day: ExternalContextDay, sourceKind: ProviderSourceKind) throws -> URI {
        guard var components = URLComponents(string: sourceURL(for: sourceKind)) else {
            throw Abort(.internalServerError, reason: "Failed to build Open-Meteo weather URL")
        }

        var items = [
            URLQueryItem(name: "latitude", value: String(configuration.latitude)),
            URLQueryItem(name: "longitude", value: String(configuration.longitude)),
            URLQueryItem(name: "timezone", value: configuration.queryTimeZone),
            URLQueryItem(name: "hourly", value: configuration.hourlyFields.joined(separator: ","))
        ]

        switch sourceKind {
        case .forecast:
            items.append(URLQueryItem(name: "past_days", value: "1"))
            items.append(URLQueryItem(name: "forecast_days", value: "2"))
        case .historical:
            items.append(URLQueryItem(name: "start_date", value: day.stringValue))
            items.append(URLQueryItem(name: "end_date", value: day.stringValue))
        }

        components.queryItems = items

        guard let url = components.url else {
            throw Abort(.internalServerError, reason: "Failed to encode Open-Meteo weather query")
        }
        return URI(string: url.absoluteString)
    }

    func makeSnapshots(from payload: ResponsePayload) throws -> [OpenMeteoWeatherHourSnapshot] {
        guard let hourly = payload.hourly else {
            throw Abort(.badGateway, reason: "Open-Meteo weather response is missing hourly section")
        }

        return try hourly.time.enumerated().map { index, timeString in
            guard let time = Self.hourFormatter.date(from: timeString) else {
                throw Abort(.badGateway, reason: "Open-Meteo weather response contains invalid hour timestamp")
            }

            return OpenMeteoWeatherHourSnapshot(
                time: time,
                weatherCode: flatten(hourly.weatherCode?[safe: index]),
                precipitation: flatten(hourly.precipitation?[safe: index]),
                temperature2m: flatten(hourly.temperature2m?[safe: index]),
                visibility: flatten(hourly.visibility?[safe: index])
            )
        }
    }

    func latestRelevantSourceUpdate(for day: ExternalContextDay, snapshots: [OpenMeteoWeatherHourSnapshot]) -> Date? {
        let dayEnd = day.startOfDay.addingTimeInterval(24 * 60 * 60)
        let now = Date()
        return snapshots
            .map(\.time)
            .filter { $0 >= day.startOfDay && $0 < dayEnd && $0 <= now }
            .max()
    }

    static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()

    func flatten<T>(_ value: T??) -> T? {
        value ?? nil
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }
        return self[index]
    }
}
