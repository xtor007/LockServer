import Foundation
import LockServerContracts
import XCTest
@testable import ExternalContextService

final class MockAirAlertsProviderClientTests: XCTestCase {
    func testGeneratesDeterministicSortedIntervalsWithinDay() async throws {
        let client = MockAirAlertsProviderClient(configuration: .kyivDefault)
        let day = try ExternalContextDay("2026-04-22")

        let first = try await client.fetchAirAlerts(for: day)
        let second = try await client.fetchAirAlerts(for: day)

        XCTAssertEqual(first, second)
        XCTAssertFalse(first.rawPayload.intervals.isEmpty)
        XCTAssertEqual(first.rawPayload.day, "2026-04-22")
        XCTAssertEqual(first.rawPayload.city, "Kyiv")

        for (index, interval) in first.rawPayload.intervals.enumerated() {
            XCTAssertGreaterThan(interval.endedAt, interval.startedAt)
            XCTAssertGreaterThanOrEqual(interval.startedAt, day.startOfDay)
            XCTAssertLessThanOrEqual(interval.endedAt, day.startOfDay.addingTimeInterval(24 * 60 * 60))
            if index > 0 {
                XCTAssertGreaterThanOrEqual(interval.startedAt, first.rawPayload.intervals[index - 1].endedAt)
            }
        }
    }

    func testResolvedValuePreservesNormalizedIntervals() {
        let intervals = [
            AirAlertInterval(startedAt: isoDate("2026-04-22T09:10:00Z"), endedAt: isoDate("2026-04-22T10:00:00Z")),
            AirAlertInterval(startedAt: isoDate("2026-04-22T07:15:00Z"), endedAt: isoDate("2026-04-22T08:20:00Z"))
        ]

        let aggregate = AirAlertsContextAggregator.makeSourceAggregate(
            rawPayload: MockAirAlertsRawPayload(
                day: "2026-04-22",
                city: "Kyiv",
                generatedAt: isoDate("2026-04-22T10:00:00Z"),
                intervals: intervals
            )
        )
        let resolved = AirAlertsContextAggregator.makeResolvedValue(sourceAggregate: aggregate)

        XCTAssertEqual(resolved.intervals.count, 2)
        XCTAssertEqual(resolved.intervals[0].startedAt, isoDate("2026-04-22T07:15:00Z"))
        XCTAssertEqual(resolved.intervals[1].startedAt, isoDate("2026-04-22T09:10:00Z"))
    }
}

private func isoDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)!
}
