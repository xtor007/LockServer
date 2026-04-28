import XCTest
@testable import AttendanceAnalysisService
import LockServerContracts

final class AttendanceAirAlertImpactCalculatorTests: XCTestCase {
    func testCalculatesPreArrivalAndGapMinutes() {
        let arrivalTime = date("2026-04-24T09:00:00Z")
        let sessions = [
            AttendanceDebugSession(
                start: date("2026-04-24T09:00:00Z"),
                end: date("2026-04-24T12:00:00Z"),
                workedMinutes: 180
            ),
            AttendanceDebugSession(
                start: date("2026-04-24T13:00:00Z"),
                end: date("2026-04-24T18:00:00Z"),
                workedMinutes: 300
            )
        ]
        let intervals = [
            AirAlertInterval(
                startedAt: date("2026-04-24T08:30:00Z"),
                endedAt: date("2026-04-24T09:15:00Z")
            ),
            AirAlertInterval(
                startedAt: date("2026-04-24T12:20:00Z"),
                endedAt: date("2026-04-24T12:50:00Z")
            )
        ]

        let breakdown = AttendanceAirAlertImpactCalculator.breakdown(
            arrivalTime: arrivalTime,
            sessionRanges: sessions,
            intervals: intervals
        )

        XCTAssertEqual(breakdown?.preArrivalMinutes, 30)
        XCTAssertEqual(breakdown?.gapMinutes, 30)
        XCTAssertEqual(breakdown?.totalMinutes, 60)
    }

    func testReturnsZeroForValidContextWithoutAlerts() {
        let totalMinutes = AttendanceAirAlertImpactCalculator.totalMinutes(
            arrivalTime: date("2026-04-24T09:00:00Z"),
            sessionRanges: [],
            intervals: []
        )

        XCTAssertEqual(totalMinutes, 0)
    }
}

private extension AttendanceAirAlertImpactCalculatorTests {
    func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}
