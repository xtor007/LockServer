import Foundation
import Vapor

struct PTVTrafficRouteSnapshot: Codable, Equatable {
    let label: String
    let distanceMeters: Double
    let travelTimeSeconds: Double
    let trafficDelaySeconds: Double
}

struct PTVTrafficProviderFetchOutput: Equatable {
    let providerMode: String
    let routes: [PTVTrafficRouteSnapshot]
}

struct PTVTrafficProviderClient {
    private let client: Client
    private let apiKey: String
    private let configuration: PTVTrafficConfiguration
    private let decoder: JSONDecoder

    init(client: Client, apiKey: String, configuration: PTVTrafficConfiguration) {
        self.client = client
        self.apiKey = apiKey
        self.configuration = configuration
        self.decoder = JSONDecoder()
    }

    func fetchTraffic(at arrivalTime: Date) async throws -> PTVTrafficProviderFetchOutput {
        let mode = providerMode(for: arrivalTime)
        var snapshots = [PTVTrafficRouteSnapshot]()
        snapshots.reserveCapacity(configuration.representativeRoutes.count)

        for route in configuration.representativeRoutes {
            snapshots.append(try await fetchRoute(route, arrivalTime: arrivalTime, providerMode: mode))
        }

        return PTVTrafficProviderFetchOutput(
            providerMode: mode.rawValue,
            routes: snapshots
        )
    }
}

private extension PTVTrafficProviderClient {
    enum ProviderMode: String {
        case average = "AVERAGE"
        case realistic = "REALISTIC"
    }

    struct RoutingResponse: Decodable {
        let distance: Double?
        let travelTime: Double?
        let trafficDelay: Double?
    }

    func providerMode(for arrivalTime: Date) -> ProviderMode {
        let now = Date()
        let delta = abs(arrivalTime.timeIntervalSince(now))
        let sameUTCDate = Calendar(identifier: .gregorian).isDate(arrivalTime, inSameDayAs: now)
        return sameUTCDate && delta <= 3 * 60 * 60 ? .realistic : .average
    }

    func fetchRoute(
        _ route: PTVTrafficConfiguration.RepresentativeRoute,
        arrivalTime: Date,
        providerMode: ProviderMode
    ) async throws -> PTVTrafficRouteSnapshot {
        guard let uri = try makeURI(route: route, arrivalTime: arrivalTime, providerMode: providerMode) else {
            throw Abort(.internalServerError, reason: "Failed to build PTV routing URI")
        }

        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: "ApiKey", value: apiKey)

        let response = try await client.send(.GET, headers: headers, to: uri)
        guard response.status == .ok, let body = response.body else {
            let reason = response.body.flatMap {
                $0.getString(at: $0.readerIndex, length: $0.readableBytes)
            } ?? "PTV routing request failed"
            throw Abort(.badGateway, reason: reason)
        }

        let payload = try decoder.decode(RoutingResponse.self, from: Data(buffer: body))
        guard let distance = payload.distance, let travelTime = payload.travelTime else {
            throw Abort(.badGateway, reason: "PTV routing response is missing distance or travelTime")
        }

        return PTVTrafficRouteSnapshot(
            label: route.label,
            distanceMeters: distance,
            travelTimeSeconds: travelTime,
            trafficDelaySeconds: payload.trafficDelay ?? 0
        )
    }

    func makeURI(
        route: PTVTrafficConfiguration.RepresentativeRoute,
        arrivalTime: Date,
        providerMode: ProviderMode
    ) throws -> URI? {
        var components = URLComponents(string: configuration.sourceURL)
        components?.queryItems = [
            URLQueryItem(name: "waypoints", value: "\(route.from.latitude),\(route.from.longitude)"),
            URLQueryItem(name: "waypoints", value: "\(route.to.latitude),\(route.to.longitude)"),
            URLQueryItem(name: "profile", value: configuration.profile),
            URLQueryItem(name: "options[trafficMode]", value: providerMode.rawValue),
            URLQueryItem(name: "options[startTime]", value: ISO8601DateFormatter().string(from: arrivalTime))
        ]
        guard let urlString = components?.url?.absoluteString else {
            return nil
        }
        return URI(string: urlString)
    }
}
