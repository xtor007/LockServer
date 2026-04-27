import Foundation
import LockServerContracts

struct WeatherSourceAggregate: Codable, Equatable {
    let observedAt: Date
    let precipitation: Double?
    let isIcy: Bool
    let visibility: Double?
}

enum WeatherContextAggregator {
    static func makeResolvedValue(sourceAggregate: WeatherSourceAggregate) -> WeatherContextResolvedValue {
        WeatherContextResolvedValue(
            weatherScore: score(for: sourceAggregate),
            precipitation: sourceAggregate.precipitation,
            isIcy: sourceAggregate.isIcy,
            visibility: sourceAggregate.visibility
        )
    }

    static func makeSourceAggregate(snapshot: OpenMeteoWeatherHourSnapshot) -> WeatherSourceAggregate {
        WeatherSourceAggregate(
            observedAt: snapshot.time,
            precipitation: snapshot.precipitation,
            isIcy: isIcyCondition(snapshot: snapshot),
            visibility: snapshot.visibility
        )
    }
}

private extension WeatherContextAggregator {
    static func score(for sourceAggregate: WeatherSourceAggregate) -> Double {
        var score = 0.0

        if sourceAggregate.isIcy {
            score += 7.0
        }

        let precipitation = sourceAggregate.precipitation ?? 0
        switch precipitation {
        case 5...:
            score += 4.0
        case 2..<5:
            score += 3.0
        case 0.5..<2:
            score += 1.5
        case 0.1..<0.5:
            score += 0.5
        default:
            break
        }

        let visibility = sourceAggregate.visibility ?? 100_000
        switch visibility {
        case ...500:
            score += 3.0
        case ...1_500:
            score += 2.0
        case ...5_000:
            score += 1.5
        case ...10_000:
            score += 1.0
        case ...20_000:
            score += 0.5
        case ...50_000:
            score += 0.2
        default:
            break
        }

        return round(min(score, 10) * 10) / 10
    }

    static func isIcyCondition(snapshot: OpenMeteoWeatherHourSnapshot) -> Bool {
        let precipitation = snapshot.precipitation ?? 0
        let temperature = snapshot.temperature2m ?? 99
        let weatherCode = snapshot.weatherCode
        return weatherCode == 66 || weatherCode == 67 || (temperature <= 0 && precipitation > 0)
    }
}
