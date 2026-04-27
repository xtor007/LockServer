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
    public let values: [ExternalContextHourValue]

    public init(factor: String, values: [ExternalContextHourValue]) {
        self.factor = factor
        self.values = values
    }
}

public struct ExternalContextFactorResponse: Content, Codable, Equatable {
    public let day: String
    public let factor: String
    public let values: [ExternalContextHourValue]

    public init(day: String, factor: String, values: [ExternalContextHourValue]) {
        self.day = day
        self.factor = factor
        self.values = values
    }
}

public struct TrafficContextResolveRequest: Content, Codable, Equatable {
    public let day: String
    public let arrivalTime: Date

    public init(day: String, arrivalTime: Date) {
        self.day = day
        self.arrivalTime = arrivalTime
    }
}

public struct PowerContextResolveRequest: Content, Codable, Equatable {
    public let day: String
    public let arrivalTime: Date

    public init(day: String, arrivalTime: Date) {
        self.day = day
        self.arrivalTime = arrivalTime
    }
}

public struct WeatherContextResolveRequest: Content, Codable, Equatable {
    public let day: String
    public let arrivalTime: Date

    public init(day: String, arrivalTime: Date) {
        self.day = day
        self.arrivalTime = arrivalTime
    }
}

public struct ExternalContextHourValue: Content, Codable, Equatable {
    public let arrivalHour: Int
    public let score: Double?
    public let weather: WeatherContextResolvedValue?

    public init(arrivalHour: Int, score: Double?, weather: WeatherContextResolvedValue? = nil) {
        self.arrivalHour = arrivalHour
        self.score = score
        self.weather = weather
    }

    enum CodingKeys: String, CodingKey {
        case arrivalHour
        case score
        case weather
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(arrivalHour, forKey: .arrivalHour)
        if let score {
            try container.encode(score, forKey: .score)
        } else {
            try container.encodeNil(forKey: .score)
        }
        if let weather {
            try container.encode(weather, forKey: .weather)
        }
    }
}

public struct TrafficContextResolvedValue: Content, Codable, Equatable {
    public let trafficScore: Double

    public init(trafficScore: Double) {
        self.trafficScore = trafficScore
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
