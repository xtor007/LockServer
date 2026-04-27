import Foundation
import Vapor
import XCTest
@testable import ExternalContextService

final class AlertsInUAAirAlertsProviderClientTests: XCTestCase {
    func testDecodesAlertsInUAHistoryPayloadAndKeepsRequestedDayAlerts() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        let client = AlertsInUAAirAlertsProviderClient(
            client: app.client,
            apiToken: "token",
            configuration: .kyivDefault
        )
        let day = try ExternalContextDay("2026-04-22")

        let rawPayload = try client.makeRawPayload(
            from: client.decodeHistoryResponse(from: Data(samplePayload.utf8)),
            for: day
        )

        XCTAssertEqual(rawPayload.day, "2026-04-22")
        XCTAssertEqual(rawPayload.city, "Kyiv")
        XCTAssertEqual(rawPayload.alerts.count, 3)
        XCTAssertEqual(rawPayload.alerts.map(\.id), ["101", "102", "103"])
        XCTAssertEqual(rawPayload.sourceUpdatedAt, isoDate("2026-04-22T12:35:20.000Z"))
    }

    func testRejectsDatesOutsideDocumentedMonthAgoWindow() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        let client = AlertsInUAAirAlertsProviderClient(
            client: app.client,
            apiToken: "token",
            configuration: .kyivDefault
        )

        XCTAssertThrowsError(try client.validate(day: try ExternalContextDay("2026-03-01")))
    }
}

private let samplePayload = """
{
  "alerts": [
    {
      "id": 101,
      "location_title": "м. Київ",
      "location_type": "city",
      "started_at": "2026-04-21T23:40:00.000Z",
      "finished_at": "2026-04-22T00:15:00.000Z",
      "updated_at": "2026-04-22T00:15:20.000Z",
      "alert_type": "air_raid",
      "location_uid": "31",
      "location_oblast": "м. Київ",
      "location_oblast_uid": 31,
      "location_raion": null,
      "notes": "",
      "calculated": false
    },
    {
      "id": 102,
      "location_title": "м. Київ",
      "location_type": "city",
      "started_at": "2026-04-22T10:05:00.000Z",
      "finished_at": "2026-04-22T11:10:00.000Z",
      "updated_at": "2026-04-22T11:10:00.000Z",
      "alert_type": "air_raid",
      "location_uid": "31",
      "location_oblast": "м. Київ",
      "location_oblast_uid": 31,
      "location_raion": null,
      "notes": "official",
      "calculated": false
    },
    {
      "id": 103,
      "location_title": "м. Київ",
      "location_type": "city",
      "started_at": "2026-04-22T12:10:00.000Z",
      "finished_at": null,
      "updated_at": "2026-04-22T12:35:20.000Z",
      "alert_type": "air_raid",
      "location_uid": "31",
      "location_oblast": "м. Київ",
      "location_oblast_uid": 31,
      "location_raion": null,
      "notes": "",
      "calculated": true
    },
    {
      "id": 104,
      "location_title": "м. Київ",
      "location_type": "city",
      "started_at": "2026-04-23T01:00:00.000Z",
      "finished_at": "2026-04-23T01:20:00.000Z",
      "updated_at": "2026-04-23T01:20:00.000Z",
      "alert_type": "air_raid",
      "location_uid": "31",
      "location_oblast": "м. Київ",
      "location_oblast_uid": 31,
      "location_raion": null,
      "notes": "",
      "calculated": false
    }
  ]
}
"""

private func isoDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)!
}
