import Foundation
import Vapor

public enum ExternalContextFactor: String, Codable, CaseIterable {
    case airAlerts = "air_alerts"
    case traffic = "traffic"
    case powerAvailability = "power_availability"
    case weather = "weather"
}

public enum ExternalContextFetchStatus: String, Codable {
    case cached
    case fetched
    case failed
}

public struct ExternalContextDayResponse: Content, Codable, Equatable {
    public let day: String
    public let contexts: [ExternalContextDayFactorResponse]

    public init(day: String, contexts: [ExternalContextDayFactorResponse]) {
        self.day = day
        self.contexts = contexts
    }
}

public struct ExternalContextDayFactorResponse: Content, Codable, Equatable {
    public let factor: String
    public let values: [ExternalContextHourValue]?
    public let intervals: [AirAlertInterval]?

    public init(
        factor: String,
        values: [ExternalContextHourValue]? = nil,
        intervals: [AirAlertInterval]? = nil
    ) {
        self.factor = factor
        self.values = values
        self.intervals = intervals
    }
}

public struct ExternalContextFactorResponse: Content, Codable, Equatable {
    public let day: String
    public let factor: String
    public let values: [ExternalContextHourValue]?
    public let intervals: [AirAlertInterval]?

    public init(
        day: String,
        factor: String,
        values: [ExternalContextHourValue]? = nil,
        intervals: [AirAlertInterval]? = nil
    ) {
        self.day = day
        self.factor = factor
        self.values = values
        self.intervals = intervals
    }
}

public struct ExternalContextHourValue: Content, Codable, Equatable {
    public let arrivalHour: Int
    public let score: Double?
    public let weather: WeatherContextResolvedValue?

    public init(
        arrivalHour: Int,
        score: Double?,
        weather: WeatherContextResolvedValue? = nil
    ) {
        self.arrivalHour = arrivalHour
        self.score = score
        self.weather = weather
    }
}

public struct TrafficContextResolvedValue: Content, Codable, Equatable {
    public let trafficScore: Double

    public init(trafficScore: Double) {
        self.trafficScore = trafficScore
    }
}

public struct AirAlertInterval: Content, Codable, Equatable {
    public let startedAt: Date
    public let endedAt: Date

    public init(startedAt: Date, endedAt: Date) {
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct AirAlertsContextResolvedValue: Content, Codable, Equatable {
    public let intervals: [AirAlertInterval]

    public init(intervals: [AirAlertInterval]) {
        self.intervals = intervals
    }
}

public struct PowerContextResolvedValue: Content, Codable, Equatable {
    public let powerScore: Double?

    public init(powerScore: Double?) {
        self.powerScore = powerScore
    }

    enum CodingKeys: String, CodingKey {
        case powerScore
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let powerScore {
            try container.encode(powerScore, forKey: .powerScore)
        } else {
            try container.encodeNil(forKey: .powerScore)
        }
    }
}

public struct WeatherContextResolvedValue: Content, Codable, Equatable {
    public let weatherScore: Double
    public let precipitation: Double?
    public let isIcy: Bool
    public let visibility: Double?

    public init(
        weatherScore: Double,
        precipitation: Double?,
        isIcy: Bool,
        visibility: Double?
    ) {
        self.weatherScore = weatherScore
        self.precipitation = precipitation
        self.isIcy = isIcy
        self.visibility = visibility
    }
}
