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
    public let values: [TrafficContextHourScore]

    public init(factor: String, values: [TrafficContextHourScore]) {
        self.factor = factor
        self.values = values
    }
}

public struct ExternalContextFactorResponse: Content, Codable, Equatable {
    public let day: String
    public let factor: String
    public let values: [TrafficContextHourScore]

    public init(day: String, factor: String, values: [TrafficContextHourScore]) {
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

public struct TrafficContextHourScore: Content, Codable, Equatable {
    public let arrivalHour: Int
    public let trafficScore: Double

    public init(arrivalHour: Int, trafficScore: Double) {
        self.arrivalHour = arrivalHour
        self.trafficScore = trafficScore
    }
}

public struct TrafficContextResolvedValue: Content, Codable, Equatable {
    public let trafficScore: Double

    public init(trafficScore: Double) {
        self.trafficScore = trafficScore
    }
}
