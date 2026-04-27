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
        XCTAssertFalse(first.rawPayload.alerts.isEmpty)
        XCTAssertEqual(first.rawPayload.day, "2026-04-22")
        XCTAssertEqual(first.rawPayload.city, "Kyiv")

        let aggregate = AirAlertsContextAggregator.makeSourceAggregate(day: day, rawPayload: first.rawPayload)

        for (index, interval) in aggregate.intervals.enumerated() {
            XCTAssertGreaterThan(interval.endedAt, interval.startedAt)
            XCTAssertGreaterThanOrEqual(interval.startedAt, day.startOfDay)
            XCTAssertLessThanOrEqual(interval.endedAt, day.startOfDay.addingTimeInterval(24 * 60 * 60))
            if index > 0 {
                XCTAssertGreaterThanOrEqual(interval.startedAt, aggregate.intervals[index - 1].endedAt)
            }
        }
    }

    func testResolvedValuePreservesNormalizedIntervals() {
        let alerts = [
            AirAlertsRawAlert(
                id: "2",
                locationTitle: "Kyiv",
                locationUID: "31",
                alertType: "air_raid",
                startedAt: isoDate("2026-04-22T09:10:00Z"),
                finishedAt: isoDate("2026-04-22T10:00:00Z"),
                updatedAt: isoDate("2026-04-22T10:00:00Z"),
                notes: nil,
                calculated: false
            ),
            AirAlertsRawAlert(
                id: "1",
                locationTitle: "Kyiv",
                locationUID: "31",
                alertType: "air_raid",
                startedAt: isoDate("2026-04-22T07:15:00Z"),
                finishedAt: isoDate("2026-04-22T08:20:00Z"),
                updatedAt: isoDate("2026-04-22T08:20:00Z"),
                notes: nil,
                calculated: false
            )
        ]
        let day = try! ExternalContextDay("2026-04-22")

        let aggregate = AirAlertsContextAggregator.makeSourceAggregate(
            day: day,
            rawPayload: AirAlertsRawPayload(
                day: "2026-04-22",
                city: "Kyiv",
                sourceKind: "mock-air-alerts-randomized",
                sourceUpdatedAt: isoDate("2026-04-22T10:00:00Z"),
                alerts: alerts
            )
        )
        let resolved = AirAlertsContextAggregator.makeResolvedValue(sourceAggregate: aggregate)

        XCTAssertEqual(resolved.intervals.count, 2)
        XCTAssertEqual(resolved.intervals[0].startedAt, isoDate("2026-04-22T07:15:00Z"))
        XCTAssertEqual(resolved.intervals[1].startedAt, isoDate("2026-04-22T09:10:00Z"))
    }

    func testAggregatorClipsCrossDayIntervalsAndIgnoresNonAirRaidAlerts() {
        let day = try! ExternalContextDay("2026-04-22")
        let aggregate = AirAlertsContextAggregator.makeSourceAggregate(
            day: day,
            rawPayload: AirAlertsRawPayload(
                day: "2026-04-22",
                city: "Kyiv",
                sourceKind: "alerts-in-ua-history:month_ago",
                sourceUpdatedAt: isoDate("2026-04-22T23:59:00Z"),
                alerts: [
                    AirAlertsRawAlert(
                        id: "left",
                        locationTitle: "Kyiv",
                        locationUID: "31",
                        alertType: "air_raid",
                        startedAt: isoDate("2026-04-21T23:40:00Z"),
                        finishedAt: isoDate("2026-04-22T00:20:00Z"),
                        updatedAt: isoDate("2026-04-22T00:20:00Z"),
                        notes: nil,
                        calculated: false
                    ),
                    AirAlertsRawAlert(
                        id: "ignored",
                        locationTitle: "Kyiv",
                        locationUID: "31",
                        alertType: "chemical",
                        startedAt: isoDate("2026-04-22T09:00:00Z"),
                        finishedAt: isoDate("2026-04-22T09:30:00Z"),
                        updatedAt: isoDate("2026-04-22T09:30:00Z"),
                        notes: nil,
                        calculated: false
                    ),
                    AirAlertsRawAlert(
                        id: "right",
                        locationTitle: "Kyiv",
                        locationUID: "31",
                        alertType: "air_raid",
                        startedAt: isoDate("2026-04-22T23:20:00Z"),
                        finishedAt: isoDate("2026-04-23T00:30:00Z"),
                        updatedAt: isoDate("2026-04-23T00:30:00Z"),
                        notes: nil,
                        calculated: false
                    )
                ]
            )
        )

        XCTAssertEqual(aggregate.intervals.count, 2)
        XCTAssertEqual(aggregate.intervals[0], AirAlertInterval(startedAt: isoDate("2026-04-22T00:00:00Z"), endedAt: isoDate("2026-04-22T00:20:00Z")))
        XCTAssertEqual(aggregate.intervals[1], AirAlertInterval(startedAt: isoDate("2026-04-22T23:20:00Z"), endedAt: isoDate("2026-04-23T00:00:00Z")))
    }
}

private func isoDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)!
}
