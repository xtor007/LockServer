import Fluent
import Foundation
import LockServerContracts
import Vapor

struct ExternalContextManager {
    private let trafficProvider: PTVTrafficProviderClient?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(trafficProvider: PTVTrafficProviderClient?) {
        self.trafficProvider = trafficProvider

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }
}

extension ExternalContextManager {
    func contexts(for dayString: String, on database: Database) async throws -> ExternalContextDayResponse {
        let day = try ExternalContextDay(dayString)
        let items = try await ExternalContextCache.query(on: database)
            .filter(\.$day == day.startOfDay)
            .sort(\.$factor, .ascending)
            .all()
            .map(makeDayFactorResponse)

        return ExternalContextDayResponse(day: day.stringValue, contexts: items)
    }

    func context(for dayString: String, factorString: String, on database: Database) async throws -> ExternalContextFactorResponse {
        let day = try ExternalContextDay(dayString)
        guard let factor = ExternalContextFactor(rawValue: factorString) else {
            throw Abort(.badRequest, reason: "Unsupported external context factor")
        }
        guard let entry = try await findEntry(day: day, factor: factor, on: database) else {
            throw Abort(.notFound, reason: "External context not found")
        }
        return makeFactorResponse(entry)
    }

    func resolveTraffic(_ request: TrafficContextResolveRequest, on database: Database) async throws -> TrafficContextResolvedValue {
        let day = try ExternalContextDay(request.day)
        let factor = ExternalContextFactor.traffic
        let city = trafficProviderCity
        let bucketKey = hourBucketKey(for: request.arrivalTime)

        let existing = try await findEntry(day: day, factor: factor, on: database)
        let resolvedEnvelope = decodeResolvedEnvelope(existing?.resolvedValueJson)

        if let resolvedValue = resolvedEnvelope.buckets[bucketKey] {
            return resolvedValue
        }

        guard let trafficProvider else {
            throw Abort(.serviceUnavailable, reason: "PTV traffic provider is not configured")
        }

        let fetchOutput = try await trafficProvider.fetchTraffic(at: request.arrivalTime)
        let sourceAggregate = TrafficContextAggregator.makeSourceAggregate(providerMode: fetchOutput.providerMode, routes: fetchOutput.routes)
        let resolvedValue = TrafficContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)

        let fetchedAt = Date()
        _ = try await upsertTrafficEntry(
            existing: existing,
            day: day,
            city: city,
            bucketKey: bucketKey,
            sourceAggregate: sourceAggregate,
            resolvedValue: resolvedValue,
            fetchedAt: fetchedAt,
            on: database
        )

        return resolvedValue
    }
}

private extension ExternalContextManager {
    var trafficSourceName: String {
        PTVTrafficConfiguration.kyivDefault.sourceName
    }

    var trafficSourceURL: String {
        PTVTrafficConfiguration.kyivDefault.sourceURL
    }

    var trafficProviderCity: String {
        PTVTrafficConfiguration.kyivDefault.city
    }

    struct RawPayloadEnvelope: Codable {
        var buckets: [String: TrafficSourceAggregate]
    }

    struct ParsedPayloadEnvelope: Codable {
        var buckets: [String: TrafficContextResolvedValue]
    }

    struct ResolvedPayloadEnvelope: Codable {
        var buckets: [String: TrafficContextResolvedValue]
    }

    func findEntry(day: ExternalContextDay, factor: ExternalContextFactor, on database: Database) async throws -> ExternalContextCache? {
        try await ExternalContextCache.query(on: database)
            .filter(\.$day == day.startOfDay)
            .filter(\.$factor == factor.rawValue)
            .filter(\.$city == trafficProviderCity)
            .first()
    }

    func upsertTrafficEntry(
        existing: ExternalContextCache?,
        day: ExternalContextDay,
        city: String,
        bucketKey: String,
        sourceAggregate: TrafficSourceAggregate,
        resolvedValue: TrafficContextResolvedValue,
        fetchedAt: Date,
        on database: Database
    ) async throws -> ExternalContextCache {
        var rawEnvelope = decodeRawEnvelope(existing?.rawPayloadJson)
        var parsedEnvelope = decodeParsedEnvelope(existing?.parsedPayloadJson)
        var resolvedEnvelope = decodeResolvedEnvelope(existing?.resolvedValueJson)

        rawEnvelope.buckets[bucketKey] = sourceAggregate
        parsedEnvelope.buckets[bucketKey] = resolvedValue
        resolvedEnvelope.buckets[bucketKey] = resolvedValue

        let rawPayloadJson = try encode(rawEnvelope)
        let parsedPayloadJson = try encode(parsedEnvelope)
        let resolvedValueJson = try encode(resolvedEnvelope)

        if let existing {
            existing.sourceName = trafficSourceName
            existing.sourceURL = trafficSourceURL
            existing.fetchStatus = ExternalContextFetchStatus.fetched.rawValue
            existing.rawPayloadJson = rawPayloadJson
            existing.parsedPayloadJson = parsedPayloadJson
            existing.resolvedValueJson = resolvedValueJson
            existing.fetchedAt = fetchedAt
            try await existing.update(on: database)
            return existing
        }

        let entry = ExternalContextCache(
            factor: ExternalContextFactor.traffic.rawValue,
            day: day.startOfDay,
            city: city,
            sourceName: trafficSourceName,
            sourceURL: trafficSourceURL,
            fetchStatus: ExternalContextFetchStatus.fetched.rawValue,
            rawPayloadJson: rawPayloadJson,
            parsedPayloadJson: parsedPayloadJson,
            resolvedValueJson: resolvedValueJson,
            fetchedAt: fetchedAt
        )
        try await entry.create(on: database)
        return entry
    }

    func makeDayFactorResponse(_ entry: ExternalContextCache) -> ExternalContextDayFactorResponse {
        ExternalContextDayFactorResponse(
            factor: entry.factor,
            values: makeHourScores(from: entry.resolvedValueJson)
        )
    }

    func makeFactorResponse(_ entry: ExternalContextCache) -> ExternalContextFactorResponse {
        ExternalContextFactorResponse(
            day: ExternalContextDay(date: entry.day).stringValue,
            factor: entry.factor,
            values: makeHourScores(from: entry.resolvedValueJson)
        )
    }

    func hourBucketKey(for arrivalTime: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(abbreviation: "UTC")!
        let hour = calendar.component(.hour, from: arrivalTime)
        return String(format: "%02d", hour)
    }

    func decodeRawEnvelope(_ json: String?) -> RawPayloadEnvelope {
        decodeEnvelope(json, default: RawPayloadEnvelope(buckets: [:]))
    }

    func decodeParsedEnvelope(_ json: String?) -> ParsedPayloadEnvelope {
        decodeEnvelope(json, default: ParsedPayloadEnvelope(buckets: [:]))
    }

    func decodeResolvedEnvelope(_ json: String?) -> ResolvedPayloadEnvelope {
        decodeEnvelope(json, default: ResolvedPayloadEnvelope(buckets: [:]))
    }

    func decodeEnvelope<T: Decodable>(_ json: String?, default defaultValue: T) -> T {
        guard let json else {
            return defaultValue
        }
        return (try? decoder.decode(T.self, from: Data(json.utf8))) ?? defaultValue
    }

    func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw Abort(.internalServerError, reason: "Failed to encode external context payload")
        }
        return string
    }

    func makeHourScores(from json: String?) -> [TrafficContextHourScore] {
        let resolvedEnvelope = decodeResolvedEnvelope(json)
        return resolvedEnvelope.buckets.keys.sorted().compactMap { key in
            guard let value = resolvedEnvelope.buckets[key], let arrivalHour = Int(key) else {
                return nil
            }
            return TrafficContextHourScore(arrivalHour: arrivalHour, trafficScore: value.trafficScore)
        }
    }
}
