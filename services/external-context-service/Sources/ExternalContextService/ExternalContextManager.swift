import Fluent
import Foundation
import LockServerContracts
import Vapor

struct ExternalContextManager {
    private let airAlertsProvider: (any AirAlertsProvider)?
    private let airAlertsFallbackProvider: (any AirAlertsProvider)?
    private let trafficProvider: PTVTrafficProviderClient?
    private let powerProvider: DTEKCityPowerProviderClient?
    private let weatherProvider: OpenMeteoWeatherProviderClient?
    private let trafficFallbackMode: TrafficFallbackMode
    private let powerFallbackEnabled: Bool
    private let weatherFallbackEnabled: Bool
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        airAlertsProvider: (any AirAlertsProvider)?,
        airAlertsFallbackProvider: (any AirAlertsProvider)?,
        trafficProvider: PTVTrafficProviderClient?,
        powerProvider: DTEKCityPowerProviderClient?,
        weatherProvider: OpenMeteoWeatherProviderClient?,
        trafficFallbackMode: TrafficFallbackMode,
        powerFallbackEnabled: Bool,
        weatherFallbackEnabled: Bool
    ) {
        self.airAlertsProvider = airAlertsProvider
        self.airAlertsFallbackProvider = airAlertsFallbackProvider
        self.trafficProvider = trafficProvider
        self.powerProvider = powerProvider
        self.weatherProvider = weatherProvider
        self.trafficFallbackMode = trafficFallbackMode
        self.powerFallbackEnabled = powerFallbackEnabled
        self.weatherFallbackEnabled = weatherFallbackEnabled

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }
}

enum TrafficFallbackMode {
    case disabled
    case fixtureWhenUnavailable
}

extension ExternalContextManager {
    func contexts(
        for dayString: String,
        arrivalTime: Date?,
        materializeIfNeeded: Bool,
        on database: Database
    ) async throws -> ExternalContextDayResponse {
        let day = try ExternalContextDay(dayString)

        if materializeIfNeeded {
            try await ensureDayMaterialized(day: day, arrivalTime: arrivalTime, on: database)
        }

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

    func resolveAirAlerts(day: ExternalContextDay, on database: Database) async throws -> AirAlertsContextResolvedValue {
        let factor = ExternalContextFactor.airAlerts
        let provider = preferredAirAlertsProvider(for: day)
        let city = provider?.city ?? airAlertsProviderCity

        let existing = try await findEntry(day: day, factor: factor, city: city, on: database)
        let rawEnvelope = decodeAirAlertsRawEnvelope(existing?.rawPayloadJson)
        let resolvedEnvelope = decodeAirAlertsResolvedEnvelope(existing?.resolvedValueJson)

        if shouldTrustCachedAirAlertsResolvedValue(day: day, existing: existing, provider: provider), let resolvedValue = resolvedEnvelope.value {
            return resolvedValue
        }

        let rawPayload: AirAlertsRawPayload
        let sourceName: String
        let sourceURL: String
        let fetchedAt: Date?

        if let cachedPayload = rawEnvelope.payload,
           cachedPayload.day == day.stringValue,
           shouldRefetchAirAlerts(day: day, existing: existing, provider: provider) == false {
            rawPayload = cachedPayload
            sourceName = existing?.sourceName ?? airAlertsFallbackSourceName
            sourceURL = existing?.sourceURL ?? airAlertsFallbackSourceURL
            fetchedAt = nil
        } else {
            guard let provider else {
                throw Abort(.serviceUnavailable, reason: "Air-alerts provider is not configured")
            }
            let fetchOutput = try await provider.fetchAirAlerts(for: day)
            rawPayload = fetchOutput.rawPayload
            sourceName = fetchOutput.sourceName
            sourceURL = fetchOutput.sourceURL
            fetchedAt = Date()
        }

        let sourceAggregate = AirAlertsContextAggregator.makeSourceAggregate(day: day, rawPayload: rawPayload)
        let resolvedValue = AirAlertsContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)

        _ = try await upsertAirAlertsEntry(
            existing: existing,
            day: day,
            city: city,
            sourceName: sourceName,
            rawPayload: rawPayload,
            sourceURL: sourceURL,
            sourceAggregate: sourceAggregate,
            resolvedValue: resolvedValue,
            fetchedAt: fetchedAt,
            on: database
        )

        return resolvedValue
    }

    func resolveTraffic(day: ExternalContextDay, arrivalTime: Date, on database: Database) async throws -> TrafficContextResolvedValue {
        let factor = ExternalContextFactor.traffic
        let city = trafficProviderCity
        let bucketKey = hourBucketKey(for: arrivalTime)

        let existing = try await findEntry(day: day, factor: factor, city: city, on: database)
        let resolvedEnvelope = decodeTrafficResolvedEnvelope(existing?.resolvedValueJson)

        if let resolvedValue = resolvedEnvelope.buckets[bucketKey] {
            return resolvedValue
        }

        let sourceAggregate: TrafficSourceAggregate
        let sourceName: String
        let sourceURL: String
        let fetchStatus: ExternalContextFetchStatus

        if let trafficProvider {
            do {
                let fetchOutput = try await trafficProvider.fetchTraffic(at: arrivalTime)
                sourceAggregate = TrafficContextAggregator.makeSourceAggregate(providerMode: fetchOutput.providerMode, routes: fetchOutput.routes)
                sourceName = trafficSourceName
                sourceURL = trafficSourceURL
                fetchStatus = .fetched
            } catch {
                guard trafficFallbackMode == .fixtureWhenUnavailable else {
                    throw error
                }
                sourceAggregate = TrafficContextFallback.makeSourceAggregate(for: arrivalTime)
                sourceName = trafficFallbackSourceName
                sourceURL = trafficFallbackSourceURL
                fetchStatus = .cached
            }
        } else {
            guard trafficFallbackMode == .fixtureWhenUnavailable else {
                throw Abort(.serviceUnavailable, reason: "PTV traffic provider is not configured")
            }
            sourceAggregate = TrafficContextFallback.makeSourceAggregate(for: arrivalTime)
            sourceName = trafficFallbackSourceName
            sourceURL = trafficFallbackSourceURL
            fetchStatus = .cached
        }

        let resolvedValue = TrafficContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)

        let fetchedAt = Date()
        _ = try await upsertTrafficEntry(
            existing: existing,
            day: day,
            city: city,
            sourceName: sourceName,
            sourceURL: sourceURL,
            fetchStatus: fetchStatus,
            bucketKey: bucketKey,
            sourceAggregate: sourceAggregate,
            resolvedValue: resolvedValue,
            fetchedAt: fetchedAt,
            on: database
        )

        return resolvedValue
    }

    func resolvePower(day: ExternalContextDay, arrivalTime: Date, on database: Database) async throws -> PowerContextResolvedValue {
        let factor = ExternalContextFactor.powerAvailability
        let city = powerProviderCity
        let bucketKey = hourBucketKey(for: arrivalTime)

        let existing = try await findEntry(day: day, factor: factor, city: city, on: database)
        let resolvedEnvelope = decodePowerResolvedEnvelope(existing?.resolvedValueJson)

        if let resolvedValue = resolvedEnvelope.buckets[bucketKey] {
            return resolvedValue
        }

        let sourceAggregate: PowerSourceAggregate
        let resolvedValue: PowerContextResolvedValue
        let sourceName: String
        let sourceURL: String
        let fetchStatus: ExternalContextFetchStatus
        let signals: [DTEKPowerCitySignal]
        let fetchedAt: Date?

        if day != ExternalContextDay(date: Date()) {
            guard powerFallbackEnabled else {
                throw Abort(.serviceUnavailable, reason: "Historical power fallback is disabled")
            }

            sourceAggregate = PowerContextFallback.makeSourceAggregate(for: arrivalTime)
            resolvedValue = PowerContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)
            sourceName = powerFallbackSourceName
            sourceURL = powerFallbackSourceURL
            fetchStatus = .cached
            signals = [PowerContextFallback.makeSignal(for: arrivalTime)]
            fetchedAt = Date()
        } else if let powerProvider {
            do {
                let rawEnvelope = decodePowerRawEnvelope(existing?.rawPayloadJson)
                let shouldRefetchSignals = rawEnvelope.signals.isEmpty || existing?.sourceName != powerSourceName

                if shouldRefetchSignals {
                    let fetchOutput = try await powerProvider.fetchKyivSignals()
                    signals = fetchOutput.signals
                    fetchedAt = Date()
                } else {
                    signals = rawEnvelope.signals
                    fetchedAt = nil
                }

                sourceAggregate = PowerContextAggregator.makeSourceAggregate(
                    arrivalTime: arrivalTime,
                    maxSignalAgeHours: powerMaxSignalAgeHours,
                    signals: signals
                )
                resolvedValue = PowerContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)
                sourceName = powerSourceName
                sourceURL = powerSourceURL
                fetchStatus = .fetched
            } catch {
                guard powerFallbackEnabled else {
                    throw error
                }

                sourceAggregate = PowerContextFallback.makeSourceAggregate(for: arrivalTime)
                resolvedValue = PowerContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)
                sourceName = powerFallbackSourceName
                sourceURL = powerFallbackSourceURL
                fetchStatus = .cached
                signals = [PowerContextFallback.makeSignal(for: arrivalTime)]
                fetchedAt = Date()
            }
        } else {
            guard powerFallbackEnabled else {
                throw Abort(.serviceUnavailable, reason: "DTEK power provider is not configured")
            }

            sourceAggregate = PowerContextFallback.makeSourceAggregate(for: arrivalTime)
            resolvedValue = PowerContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)
            sourceName = powerFallbackSourceName
            sourceURL = powerFallbackSourceURL
            fetchStatus = .cached
            signals = [PowerContextFallback.makeSignal(for: arrivalTime)]
            fetchedAt = Date()
        }

        _ = try await upsertPowerEntry(
            existing: existing,
            day: day,
            city: city,
            sourceName: sourceName,
            sourceURL: sourceURL,
            fetchStatus: fetchStatus,
            signals: signals,
            bucketKey: bucketKey,
            sourceAggregate: sourceAggregate,
            resolvedValue: resolvedValue,
            fetchedAt: fetchedAt,
            on: database
        )

        return resolvedValue
    }

    func resolveWeather(day: ExternalContextDay, arrivalTime: Date, on database: Database) async throws -> WeatherContextResolvedValue {
        let factor = ExternalContextFactor.weather
        let city = weatherProviderCity
        let bucketKey = hourBucketKey(for: arrivalTime)
        let observationTime = arrivalTime.addingTimeInterval(-60 * 60)

        let existing = try await findEntry(day: day, factor: factor, city: city, on: database)
        let resolvedEnvelope = decodeWeatherResolvedEnvelope(existing?.resolvedValueJson)

        if let resolvedValue = resolvedEnvelope.buckets[bucketKey] {
            return resolvedValue
        }

        var rawPayload: OpenMeteoWeatherRawPayload
        var sourceAggregate: WeatherSourceAggregate
        var resolvedValue: WeatherContextResolvedValue
        var sourceURL: String
        var sourceName: String
        var fetchStatus: ExternalContextFetchStatus
        var fetchedAt: Date?

        if let weatherProvider {
            do {
                let rawEnvelope = decodeWeatherRawEnvelope(existing?.rawPayloadJson)
                if let cachedPayload = rawEnvelope.payload, cachedPayload.day == day.stringValue {
                    rawPayload = cachedPayload
                    sourceURL = existing?.sourceURL ?? weatherDefaultSourceURL(for: day)
                    fetchedAt = nil
                } else {
                    let fetchOutput = try await weatherProvider.fetchWeather(for: day)
                    rawPayload = fetchOutput.rawPayload
                    sourceURL = fetchOutput.sourceURL
                    fetchedAt = Date()
                }

                guard let sourceSnapshot = weatherSnapshot(from: rawPayload, for: observationTime) else {
                    throw Abort(.badGateway, reason: "Open-Meteo weather response does not contain requested hour-before-arrival bucket")
                }
                sourceAggregate = WeatherContextAggregator.makeSourceAggregate(snapshot: sourceSnapshot)
                resolvedValue = WeatherContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)
                sourceName = weatherSourceName
                fetchStatus = .fetched
            } catch {
                guard weatherFallbackEnabled else {
                    throw error
                }

                let fallback = WeatherContextFallback.makeOutput(for: day, arrivalTime: arrivalTime)
                rawPayload = fallback.rawPayload
                sourceAggregate = fallback.sourceAggregate
                resolvedValue = fallback.resolvedValue
                sourceURL = weatherFallbackSourceURL
                sourceName = weatherFallbackSourceName
                fetchStatus = .cached
                fetchedAt = Date()
            }
        } else {
            guard weatherFallbackEnabled else {
                throw Abort(.serviceUnavailable, reason: "Open-Meteo weather provider is not configured")
            }

            let fallback = WeatherContextFallback.makeOutput(for: day, arrivalTime: arrivalTime)
            rawPayload = fallback.rawPayload
            sourceAggregate = fallback.sourceAggregate
            resolvedValue = fallback.resolvedValue
            sourceURL = weatherFallbackSourceURL
            sourceName = weatherFallbackSourceName
            fetchStatus = .cached
            fetchedAt = Date()
        }

        _ = try await upsertWeatherEntry(
            existing: existing,
            day: day,
            city: city,
            sourceName: sourceName,
            rawPayload: rawPayload,
            sourceURL: sourceURL,
            fetchStatus: fetchStatus,
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
    var airAlertsFallbackSourceName: String {
        MockAirAlertsConfiguration.kyivDefault.sourceName
    }

    var airAlertsFallbackSourceURL: String {
        MockAirAlertsConfiguration.kyivDefault.sourceURL
    }

    var airAlertsProviderCity: String {
        airAlertsProvider?.city ?? MockAirAlertsConfiguration.kyivDefault.city
    }

    var airAlertsCurrentDayRefreshInterval: TimeInterval {
        TimeInterval(AlertsInUAAirAlertsConfiguration.kyivDefault.currentDayRefreshIntervalMinutes * 60)
    }

    var trafficSourceName: String {
        PTVTrafficConfiguration.kyivDefault.sourceName
    }

    var trafficSourceURL: String {
        PTVTrafficConfiguration.kyivDefault.sourceURL
    }

    var trafficProviderCity: String {
        PTVTrafficConfiguration.kyivDefault.city
    }

    var trafficFallbackSourceName: String {
        "ptv-developer-routing-fixture"
    }

    var trafficFallbackSourceURL: String {
        "fixture://traffic/dev-fallback"
    }

    var powerSourceName: String {
        DTEKCityPowerConfiguration.kyivDefault.sourceName
    }

    var powerSourceURL: String {
        DTEKCityPowerConfiguration.kyivDefault.sourceURL
    }

    var powerFallbackSourceName: String {
        "kyiv-power-fixture"
    }

    var powerFallbackSourceURL: String {
        "fixture://power/kyiv-history"
    }

    var powerProviderCity: String {
        DTEKCityPowerConfiguration.kyivDefault.city
    }

    var powerMaxSignalAgeHours: Int {
        DTEKCityPowerConfiguration.kyivDefault.maxSignalAgeHours
    }

    var weatherSourceName: String {
        OpenMeteoWeatherConfiguration.kyivDefault.sourceName
    }

    var weatherFallbackSourceName: String {
        "open-meteo-weather-fixture"
    }

    var weatherFallbackSourceURL: String {
        "fixture://weather/kyiv-history"
    }

    var weatherProviderCity: String {
        OpenMeteoWeatherConfiguration.kyivDefault.city
    }

    struct TrafficRawPayloadEnvelope: Codable {
        var buckets: [String: TrafficSourceAggregate]
    }

    struct AirAlertsRawPayloadEnvelope: Codable {
        var payload: AirAlertsRawPayload?
    }

    struct AirAlertsParsedPayloadEnvelope: Codable {
        var value: AirAlertsSourceAggregate?
    }

    struct AirAlertsResolvedPayloadEnvelope: Codable {
        var value: AirAlertsContextResolvedValue?
    }

    struct TrafficParsedPayloadEnvelope: Codable {
        var buckets: [String: TrafficContextResolvedValue]
    }

    struct TrafficResolvedPayloadEnvelope: Codable {
        var buckets: [String: TrafficContextResolvedValue]
    }

    struct PowerRawPayloadEnvelope: Codable {
        var signals: [DTEKPowerCitySignal]
    }

    struct PowerParsedPayloadEnvelope: Codable {
        var buckets: [String: PowerSourceAggregate]
    }

    struct PowerResolvedPayloadEnvelope: Codable {
        var buckets: [String: PowerContextResolvedValue]
    }

    struct WeatherRawPayloadEnvelope: Codable {
        var payload: OpenMeteoWeatherRawPayload?
    }

    struct WeatherParsedPayloadEnvelope: Codable {
        var buckets: [String: WeatherSourceAggregate]
    }

    struct WeatherResolvedPayloadEnvelope: Codable {
        var buckets: [String: WeatherContextResolvedValue]
    }

    func findEntry(day: ExternalContextDay, factor: ExternalContextFactor, on database: Database) async throws -> ExternalContextCache? {
        try await ExternalContextCache.query(on: database)
            .filter(\.$day == day.startOfDay)
            .filter(\.$factor == factor.rawValue)
            .first()
    }

    func findEntry(day: ExternalContextDay, factor: ExternalContextFactor, city: String, on database: Database) async throws -> ExternalContextCache? {
        try await ExternalContextCache.query(on: database)
            .filter(\.$day == day.startOfDay)
            .filter(\.$factor == factor.rawValue)
            .filter(\.$city == city)
            .first()
    }

    func ensureDayMaterialized(
        day: ExternalContextDay,
        arrivalTime: Date?,
        on database: Database
    ) async throws {
        _ = try await resolveAirAlerts(day: day, on: database)

        guard let arrivalTime else {
            throw Abort(.badRequest, reason: "arrivalTime query is required for external-context materialization")
        }

        _ = try await resolveTraffic(day: day, arrivalTime: arrivalTime, on: database)
        _ = try await resolvePower(day: day, arrivalTime: arrivalTime, on: database)
        _ = try await resolveWeather(day: day, arrivalTime: arrivalTime, on: database)
    }

    func upsertTrafficEntry(
        existing: ExternalContextCache?,
        day: ExternalContextDay,
        city: String,
        sourceName: String,
        sourceURL: String,
        fetchStatus: ExternalContextFetchStatus,
        bucketKey: String,
        sourceAggregate: TrafficSourceAggregate,
        resolvedValue: TrafficContextResolvedValue,
        fetchedAt: Date,
        on database: Database
    ) async throws -> ExternalContextCache {
        var rawEnvelope = decodeTrafficRawEnvelope(existing?.rawPayloadJson)
        var parsedEnvelope = decodeTrafficParsedEnvelope(existing?.parsedPayloadJson)
        var resolvedEnvelope = decodeTrafficResolvedEnvelope(existing?.resolvedValueJson)

        rawEnvelope.buckets[bucketKey] = sourceAggregate
        parsedEnvelope.buckets[bucketKey] = resolvedValue
        resolvedEnvelope.buckets[bucketKey] = resolvedValue

        let rawPayloadJson = try encode(rawEnvelope)
        let parsedPayloadJson = try encode(parsedEnvelope)
        let resolvedValueJson = try encode(resolvedEnvelope)

        if let existing {
            existing.sourceName = sourceName
            existing.sourceURL = sourceURL
            existing.fetchStatus = fetchStatus.rawValue
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
            sourceName: sourceName,
            sourceURL: sourceURL,
            fetchStatus: fetchStatus.rawValue,
            rawPayloadJson: rawPayloadJson,
            parsedPayloadJson: parsedPayloadJson,
            resolvedValueJson: resolvedValueJson,
            fetchedAt: fetchedAt
        )
        try await entry.create(on: database)
        return entry
    }

    func upsertAirAlertsEntry(
        existing: ExternalContextCache?,
        day: ExternalContextDay,
        city: String,
        sourceName: String,
        rawPayload: AirAlertsRawPayload,
        sourceURL: String,
        sourceAggregate: AirAlertsSourceAggregate,
        resolvedValue: AirAlertsContextResolvedValue,
        fetchedAt: Date?,
        on database: Database
    ) async throws -> ExternalContextCache {
        let rawEnvelope = AirAlertsRawPayloadEnvelope(payload: rawPayload)
        let parsedEnvelope = AirAlertsParsedPayloadEnvelope(value: sourceAggregate)
        let resolvedEnvelope = AirAlertsResolvedPayloadEnvelope(value: resolvedValue)

        let rawPayloadJson = try encode(rawEnvelope)
        let parsedPayloadJson = try encode(parsedEnvelope)
        let resolvedValueJson = try encode(resolvedEnvelope)
        let sourceUpdatedAt = rawPayload.sourceUpdatedAt ?? resolvedValue.intervals.map(\.endedAt).max()

        if let existing {
            existing.sourceName = sourceName
            existing.sourceURL = sourceURL
            existing.fetchStatus = ExternalContextFetchStatus.fetched.rawValue
            existing.rawPayloadJson = rawPayloadJson
            existing.parsedPayloadJson = parsedPayloadJson
            existing.resolvedValueJson = resolvedValueJson
            existing.sourceUpdatedAt = sourceUpdatedAt
            existing.fetchedAt = fetchedAt ?? existing.fetchedAt
            try await existing.update(on: database)
            return existing
        }

        let entry = ExternalContextCache(
            factor: ExternalContextFactor.airAlerts.rawValue,
            day: day.startOfDay,
            city: city,
            sourceName: sourceName,
            sourceURL: sourceURL,
            fetchStatus: ExternalContextFetchStatus.fetched.rawValue,
            rawPayloadJson: rawPayloadJson,
            parsedPayloadJson: parsedPayloadJson,
            resolvedValueJson: resolvedValueJson,
            sourceUpdatedAt: sourceUpdatedAt,
            fetchedAt: fetchedAt
        )
        try await entry.create(on: database)
        return entry
    }

    func upsertPowerEntry(
        existing: ExternalContextCache?,
        day: ExternalContextDay,
        city: String,
        sourceName: String,
        sourceURL: String,
        fetchStatus: ExternalContextFetchStatus,
        signals: [DTEKPowerCitySignal],
        bucketKey: String,
        sourceAggregate: PowerSourceAggregate,
        resolvedValue: PowerContextResolvedValue,
        fetchedAt: Date?,
        on database: Database
    ) async throws -> ExternalContextCache {
        let rawEnvelope = PowerRawPayloadEnvelope(signals: signals)
        var parsedEnvelope = decodePowerParsedEnvelope(existing?.parsedPayloadJson)
        var resolvedEnvelope = decodePowerResolvedEnvelope(existing?.resolvedValueJson)

        parsedEnvelope.buckets[bucketKey] = sourceAggregate
        resolvedEnvelope.buckets[bucketKey] = resolvedValue

        let rawPayloadJson = try encode(rawEnvelope)
        let parsedPayloadJson = try encode(parsedEnvelope)
        let resolvedValueJson = try encode(resolvedEnvelope)
        let sourceUpdatedAt = signals.map(\.publishedAt).max() ?? sourceAggregate.signalPublishedAt

        if let existing {
            existing.sourceName = sourceName
            existing.sourceURL = sourceURL
            existing.fetchStatus = fetchStatus.rawValue
            existing.rawPayloadJson = rawPayloadJson
            existing.parsedPayloadJson = parsedPayloadJson
            existing.resolvedValueJson = resolvedValueJson
            existing.sourceUpdatedAt = sourceUpdatedAt
            existing.fetchedAt = fetchedAt ?? existing.fetchedAt
            try await existing.update(on: database)
            return existing
        }

        let entry = ExternalContextCache(
            factor: ExternalContextFactor.powerAvailability.rawValue,
            day: day.startOfDay,
            city: city,
            sourceName: sourceName,
            sourceURL: sourceURL,
            fetchStatus: fetchStatus.rawValue,
            rawPayloadJson: rawPayloadJson,
            parsedPayloadJson: parsedPayloadJson,
            resolvedValueJson: resolvedValueJson,
            sourceUpdatedAt: sourceUpdatedAt,
            fetchedAt: fetchedAt
        )
        try await entry.create(on: database)
        return entry
    }

    func upsertWeatherEntry(
        existing: ExternalContextCache?,
        day: ExternalContextDay,
        city: String,
        sourceName: String,
        rawPayload: OpenMeteoWeatherRawPayload,
        sourceURL: String,
        fetchStatus: ExternalContextFetchStatus,
        bucketKey: String,
        sourceAggregate: WeatherSourceAggregate,
        resolvedValue: WeatherContextResolvedValue,
        fetchedAt: Date?,
        on database: Database
    ) async throws -> ExternalContextCache {
        let rawEnvelope = WeatherRawPayloadEnvelope(payload: rawPayload)
        var parsedEnvelope = decodeWeatherParsedEnvelope(existing?.parsedPayloadJson)
        var resolvedEnvelope = decodeWeatherResolvedEnvelope(existing?.resolvedValueJson)

        parsedEnvelope.buckets[bucketKey] = sourceAggregate
        resolvedEnvelope.buckets[bucketKey] = resolvedValue

        let rawPayloadJson = try encode(rawEnvelope)
        let parsedPayloadJson = try encode(parsedEnvelope)
        let resolvedValueJson = try encode(resolvedEnvelope)

        if let existing {
            existing.sourceName = sourceName
            existing.sourceURL = sourceURL
            existing.fetchStatus = fetchStatus.rawValue
            existing.rawPayloadJson = rawPayloadJson
            existing.parsedPayloadJson = parsedPayloadJson
            existing.resolvedValueJson = resolvedValueJson
            existing.sourceUpdatedAt = rawPayload.sourceUpdatedAt
            existing.fetchedAt = fetchedAt ?? existing.fetchedAt
            try await existing.update(on: database)
            return existing
        }

        let entry = ExternalContextCache(
            factor: ExternalContextFactor.weather.rawValue,
            day: day.startOfDay,
            city: city,
            sourceName: sourceName,
            sourceURL: sourceURL,
            fetchStatus: fetchStatus.rawValue,
            rawPayloadJson: rawPayloadJson,
            parsedPayloadJson: parsedPayloadJson,
            resolvedValueJson: resolvedValueJson,
            sourceUpdatedAt: rawPayload.sourceUpdatedAt,
            fetchedAt: fetchedAt
        )
        try await entry.create(on: database)
        return entry
    }

    func makeDayFactorResponse(_ entry: ExternalContextCache) -> ExternalContextDayFactorResponse {
        guard let factor = ExternalContextFactor(rawValue: entry.factor) else {
            return ExternalContextDayFactorResponse(factor: entry.factor, values: [])
        }

        switch factor {
        case .airAlerts:
            return ExternalContextDayFactorResponse(
                factor: entry.factor,
                intervals: decodeAirAlertsResolvedEnvelope(entry.resolvedValueJson).value?.intervals ?? []
            )
        case .traffic, .powerAvailability, .weather:
            return ExternalContextDayFactorResponse(
                factor: entry.factor,
                values: makeHourValues(from: entry.factor, json: entry.resolvedValueJson)
            )
        }
    }

    func makeFactorResponse(_ entry: ExternalContextCache) -> ExternalContextFactorResponse {
        guard let factor = ExternalContextFactor(rawValue: entry.factor) else {
            return ExternalContextFactorResponse(
                day: ExternalContextDay(date: entry.day).stringValue,
                factor: entry.factor,
                values: []
            )
        }

        switch factor {
        case .airAlerts:
            return ExternalContextFactorResponse(
                day: ExternalContextDay(date: entry.day).stringValue,
                factor: entry.factor,
                intervals: decodeAirAlertsResolvedEnvelope(entry.resolvedValueJson).value?.intervals ?? []
            )
        case .traffic, .powerAvailability, .weather:
            return ExternalContextFactorResponse(
                day: ExternalContextDay(date: entry.day).stringValue,
                factor: entry.factor,
                values: makeHourValues(from: entry.factor, json: entry.resolvedValueJson)
            )
        }
    }

    func hourBucketKey(for arrivalTime: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(abbreviation: "UTC")!
        let hour = calendar.component(.hour, from: arrivalTime)
        return String(format: "%02d", hour)
    }

    func decodeTrafficRawEnvelope(_ json: String?) -> TrafficRawPayloadEnvelope {
        decodeEnvelope(json, default: TrafficRawPayloadEnvelope(buckets: [:]))
    }

    func decodeAirAlertsRawEnvelope(_ json: String?) -> AirAlertsRawPayloadEnvelope {
        decodeEnvelope(json, default: AirAlertsRawPayloadEnvelope(payload: nil))
    }

    func preferredAirAlertsProvider(for day: ExternalContextDay) -> (any AirAlertsProvider)? {
        if let airAlertsProvider, airAlertsProvider.supports(day: day) {
            return airAlertsProvider
        }
        return airAlertsFallbackProvider
    }

    func shouldTrustCachedAirAlertsResolvedValue(
        day: ExternalContextDay,
        existing: ExternalContextCache?,
        provider: (any AirAlertsProvider)?
    ) -> Bool {
        guard existing != nil else {
            return false
        }

        if day == ExternalContextDay(date: Date()) {
            return false
        }

        guard let provider else {
            return true
        }

        return existing?.sourceName == provider.sourceName
    }

    func shouldRefetchAirAlerts(
        day: ExternalContextDay,
        existing: ExternalContextCache?,
        provider: (any AirAlertsProvider)?
    ) -> Bool {
        guard let existing else {
            return true
        }

        if let provider, existing.sourceName != provider.sourceName {
            return true
        }

        guard day == ExternalContextDay(date: Date()), provider != nil else {
            return false
        }

        guard let fetchedAt = existing.fetchedAt else {
            return true
        }

        return Date().timeIntervalSince(fetchedAt) >= airAlertsCurrentDayRefreshInterval
    }

    func decodeAirAlertsParsedEnvelope(_ json: String?) -> AirAlertsParsedPayloadEnvelope {
        decodeEnvelope(json, default: AirAlertsParsedPayloadEnvelope(value: nil))
    }

    func decodeAirAlertsResolvedEnvelope(_ json: String?) -> AirAlertsResolvedPayloadEnvelope {
        decodeEnvelope(json, default: AirAlertsResolvedPayloadEnvelope(value: nil))
    }

    func decodeTrafficParsedEnvelope(_ json: String?) -> TrafficParsedPayloadEnvelope {
        decodeEnvelope(json, default: TrafficParsedPayloadEnvelope(buckets: [:]))
    }

    func decodeTrafficResolvedEnvelope(_ json: String?) -> TrafficResolvedPayloadEnvelope {
        decodeEnvelope(json, default: TrafficResolvedPayloadEnvelope(buckets: [:]))
    }

    func decodePowerRawEnvelope(_ json: String?) -> PowerRawPayloadEnvelope {
        decodeEnvelope(json, default: PowerRawPayloadEnvelope(signals: []))
    }

    func decodePowerParsedEnvelope(_ json: String?) -> PowerParsedPayloadEnvelope {
        decodeEnvelope(json, default: PowerParsedPayloadEnvelope(buckets: [:]))
    }

    func decodePowerResolvedEnvelope(_ json: String?) -> PowerResolvedPayloadEnvelope {
        decodeEnvelope(json, default: PowerResolvedPayloadEnvelope(buckets: [:]))
    }

    func decodeWeatherRawEnvelope(_ json: String?) -> WeatherRawPayloadEnvelope {
        decodeEnvelope(json, default: WeatherRawPayloadEnvelope(payload: nil))
    }

    func decodeWeatherParsedEnvelope(_ json: String?) -> WeatherParsedPayloadEnvelope {
        decodeEnvelope(json, default: WeatherParsedPayloadEnvelope(buckets: [:]))
    }

    func decodeWeatherResolvedEnvelope(_ json: String?) -> WeatherResolvedPayloadEnvelope {
        decodeEnvelope(json, default: WeatherResolvedPayloadEnvelope(buckets: [:]))
    }

    func weatherDefaultSourceURL(for day: ExternalContextDay) -> String {
        if day == ExternalContextDay(date: Date()) {
            return OpenMeteoWeatherConfiguration.kyivDefault.forecastSourceURL
        }
        return OpenMeteoWeatherConfiguration.kyivDefault.historicalSourceURL
    }

    func weatherSnapshot(from rawPayload: OpenMeteoWeatherRawPayload, for observationTime: Date) -> OpenMeteoWeatherHourSnapshot? {
        let observationBucketKey = hourBucketKey(for: observationTime)
        return rawPayload.snapshots.first {
            hourBucketKey(for: $0.time) == observationBucketKey
        }
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

    func makeHourValues(from factorString: String, json: String?) -> [ExternalContextHourValue] {
        guard let factor = ExternalContextFactor(rawValue: factorString) else {
            return []
        }

        switch factor {
        case .traffic:
            let resolvedEnvelope = decodeTrafficResolvedEnvelope(json)
            return resolvedEnvelope.buckets.keys.sorted().compactMap { key in
                guard let value = resolvedEnvelope.buckets[key], let arrivalHour = Int(key) else {
                    return nil
                }
                return ExternalContextHourValue(arrivalHour: arrivalHour, score: value.trafficScore)
            }
        case .powerAvailability:
            let resolvedEnvelope = decodePowerResolvedEnvelope(json)
            return resolvedEnvelope.buckets.keys.sorted().compactMap { key in
                guard let value = resolvedEnvelope.buckets[key], let arrivalHour = Int(key) else {
                    return nil
                }
                return ExternalContextHourValue(arrivalHour: arrivalHour, score: value.powerScore)
            }
        case .weather:
            let resolvedEnvelope = decodeWeatherResolvedEnvelope(json)
            return resolvedEnvelope.buckets.keys.sorted().compactMap { key in
                guard let value = resolvedEnvelope.buckets[key], let arrivalHour = Int(key) else {
                    return nil
                }
                return ExternalContextHourValue(arrivalHour: arrivalHour, score: value.weatherScore, weather: value)
            }
        case .airAlerts:
            return []
        }
    }
}
