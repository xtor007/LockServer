import Foundation
import LockServerContracts
import LockServerCore

struct WeatherContextFallbackOutput {
    let rawPayload: OpenMeteoWeatherRawPayload
    let sourceAggregate: WeatherSourceAggregate
    let resolvedValue: WeatherContextResolvedValue
}

enum WeatherContextFallback {
    static func makeOutput(for day: ExternalContextDay, arrivalTime: Date) -> WeatherContextFallbackOutput {
        let snapshotTime = arrivalTime.addingTimeInterval(-60 * 60)
        let sourceAggregate = makeSourceAggregate(for: snapshotTime)
        let snapshot = OpenMeteoWeatherHourSnapshot(
            time: snapshotTime,
            weatherCode: sourceAggregate.isIcy ? 66 : nil,
            precipitation: sourceAggregate.precipitation,
            temperature2m: sourceAggregate.isIcy ? -1.5 : 9.0,
            visibility: sourceAggregate.visibility
        )

        return WeatherContextFallbackOutput(
            rawPayload: OpenMeteoWeatherRawPayload(
                day: day.stringValue,
                sourceKind: "fallback_fixture",
                queryTimeZone: "UTC",
                latitude: OpenMeteoWeatherConfiguration.kyivDefault.latitude,
                longitude: OpenMeteoWeatherConfiguration.kyivDefault.longitude,
                sourceUpdatedAt: snapshotTime,
                snapshots: [snapshot]
            ),
            sourceAggregate: sourceAggregate,
            resolvedValue: WeatherContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)
        )
    }
}

private extension WeatherContextFallback {
    enum Scenario {
        case clear
        case lightRain
        case heavyRain
        case icyMorning
        case fog
    }

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    static func makeSourceAggregate(for observationTime: Date) -> WeatherSourceAggregate {
        switch scenario(for: observationTime) {
        case .clear:
            return WeatherSourceAggregate(observedAt: observationTime, precipitation: 0, isIcy: false, visibility: 45_000)
        case .lightRain:
            return WeatherSourceAggregate(observedAt: observationTime, precipitation: 0.9, isIcy: false, visibility: 12_000)
        case .heavyRain:
            return WeatherSourceAggregate(observedAt: observationTime, precipitation: 4.8, isIcy: false, visibility: 3_200)
        case .icyMorning:
            return WeatherSourceAggregate(observedAt: observationTime, precipitation: 0.6, isIcy: true, visibility: 2_200)
        case .fog:
            return WeatherSourceAggregate(observedAt: observationTime, precipitation: 0, isIcy: false, visibility: 900)
        }
    }

    static func scenario(for observationTime: Date) -> Scenario {
        var generator = DeterministicSeededGenerator(seed: DeterministicSeededGenerator.stableSeed(for: "weather|\(hourKey(for: observationTime))"))
        let month = utcCalendar.component(.month, from: observationTime)
        let hour = utcCalendar.component(.hour, from: observationTime)
        let roll = Int.random(in: 0..<100, using: &generator)

        if [12, 1, 2].contains(month) {
            if roll < 16 && hour <= 10 {
                return .icyMorning
            }
            if roll < 28 {
                return .fog
            }
            if roll < 48 {
                return .lightRain
            }
            return .clear
        }

        if [3, 4, 10, 11].contains(month) {
            if roll < 15 {
                return .heavyRain
            }
            if roll < 38 {
                return .lightRain
            }
            if roll < 48 {
                return .fog
            }
            return .clear
        }

        if roll < 10 {
            return .heavyRain
        }
        if roll < 24 {
            return .lightRain
        }
        return .clear
    }

    static func hourKey(for observationTime: Date) -> String {
        let components = utcCalendar.dateComponents([.year, .month, .day, .hour], from: observationTime)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)-\(components.hour ?? 0)"
    }
}
