import Foundation
import XCTest
@testable import ExternalContextService

final class WeatherContextAggregatorTests: XCTestCase {
    func testResolvesExactWeatherContextForClearLowImpactWeather() {
        let snapshot = OpenMeteoWeatherHourSnapshot(
            time: isoDate("2026-04-22T08:00:00Z"),
            weatherCode: 1,
            precipitation: 0,
            temperature2m: 14,
            visibility: 20_000
        )

        let sourceAggregate = WeatherContextAggregator.makeSourceAggregate(snapshot: snapshot)
        let resolvedValue = WeatherContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)

        XCTAssertEqual(sourceAggregate.precipitation, 0)
        XCTAssertEqual(sourceAggregate.isIcy, false)
        XCTAssertEqual(sourceAggregate.visibility, 20_000)
        XCTAssertEqual(resolvedValue.weatherScore, 0.5)
        XCTAssertEqual(resolvedValue.precipitation, 0)
        XCTAssertEqual(resolvedValue.isIcy, false)
        XCTAssertEqual(resolvedValue.visibility, 20_000)
    }

    func testResolvesFreezingRainAsExactWeatherContext() {
        let snapshot = OpenMeteoWeatherHourSnapshot(
            time: isoDate("2026-01-11T07:00:00Z"),
            weatherCode: 67,
            precipitation: 2.4,
            temperature2m: -1.5,
            visibility: 1_200
        )

        let sourceAggregate = WeatherContextAggregator.makeSourceAggregate(snapshot: snapshot)
        let resolvedValue = WeatherContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)

        XCTAssertEqual(sourceAggregate.precipitation, 2.4)
        XCTAssertEqual(sourceAggregate.isIcy, true)
        XCTAssertEqual(sourceAggregate.visibility, 1_200)
        XCTAssertEqual(resolvedValue.weatherScore, 10)
        XCTAssertEqual(resolvedValue.precipitation, 2.4)
        XCTAssertEqual(resolvedValue.isIcy, true)
        XCTAssertEqual(resolvedValue.visibility, 1_200)
    }

    func testResolvesLowVisibilityWithoutInventingExtraSignals() {
        let snapshot = OpenMeteoWeatherHourSnapshot(
            time: isoDate("2026-04-27T06:00:00Z"),
            weatherCode: 45,
            precipitation: 0,
            temperature2m: 4,
            visibility: 300
        )

        let sourceAggregate = WeatherContextAggregator.makeSourceAggregate(snapshot: snapshot)
        let resolvedValue = WeatherContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)

        XCTAssertEqual(sourceAggregate.precipitation, 0)
        XCTAssertEqual(sourceAggregate.isIcy, false)
        XCTAssertEqual(sourceAggregate.visibility, 300)
        XCTAssertEqual(resolvedValue.weatherScore, 3)
        XCTAssertEqual(resolvedValue.precipitation, 0)
        XCTAssertEqual(resolvedValue.isIcy, false)
        XCTAssertEqual(resolvedValue.visibility, 300)
    }
}

private func isoDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)!
}
