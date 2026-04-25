import XCTest
@testable import AttendanceAnalysisService
import LockServerContracts

final class AttendanceObservationBuilderTests: XCTestCase {
    private let builder = AttendanceObservationBuilder()

    func testNormalFullDayProducesSingleObservation() throws {
        let outcome = builder.build(
            for: try AttendanceDay("2026-04-21"),
            logs: [
                EnterModel(isOn: true, time: makeDate("2026-04-21T09:00:00Z")),
                EnterModel(isOn: false, time: makeDate("2026-04-21T17:30:00Z"))
            ],
            workNormMinutes: 480
        )

        XCTAssertEqual(outcome.status, .observationBuilt)
        XCTAssertEqual(outcome.observation?.workedMinutes, 510)
        XCTAssertEqual(outcome.observation?.breakMinutes, 0)
        XCTAssertEqual(outcome.observation?.sessionsCount, 1)
        XCTAssertFalse(outcome.observation?.isTechnicalAnomaly ?? true)
    }

    func testMultipleSessionsAccumulateWorkedAndBreakTime() throws {
        let outcome = builder.build(
            for: try AttendanceDay("2026-04-21"),
            logs: [
                EnterModel(isOn: true, time: makeDate("2026-04-21T08:45:00Z")),
                EnterModel(isOn: false, time: makeDate("2026-04-21T12:00:00Z")),
                EnterModel(isOn: true, time: makeDate("2026-04-21T13:00:00Z")),
                EnterModel(isOn: false, time: makeDate("2026-04-21T18:00:00Z"))
            ],
            workNormMinutes: 480
        )

        XCTAssertEqual(outcome.status, .observationBuilt)
        XCTAssertEqual(outcome.observation?.workedMinutes, 495)
        XCTAssertEqual(outcome.observation?.breakMinutes, 60)
        XCTAssertEqual(outcome.observation?.sessionsCount, 2)
        XCTAssertEqual(outcome.details.completedSessionsCount, 2)
    }

    func testShortDayIsNotTechnicalAnomaly() throws {
        let outcome = builder.build(
            for: try AttendanceDay("2026-04-22"),
            logs: [
                EnterModel(isOn: true, time: makeDate("2026-04-22T10:00:00Z")),
                EnterModel(isOn: false, time: makeDate("2026-04-22T15:30:00Z"))
            ],
            workNormMinutes: 480
        )

        XCTAssertEqual(outcome.status, .observationBuilt)
        XCTAssertEqual(outcome.observation?.workedMinutes, 330)
        XCTAssertFalse(outcome.observation?.isTechnicalAnomaly ?? true)
    }

    func testMissingExitBecomesTechnicalAnomaly() throws {
        let outcome = builder.build(
            for: try AttendanceDay("2026-04-23"),
            logs: [
                EnterModel(isOn: true, time: makeDate("2026-04-23T09:15:00Z"))
            ],
            workNormMinutes: 480
        )

        XCTAssertEqual(outcome.status, .technicalAnomaly)
        XCTAssertEqual(outcome.observation?.workedMinutes, 0)
        XCTAssertEqual(outcome.observation?.sessionsCount, 1)
        XCTAssertTrue(outcome.observation?.isTechnicalAnomaly ?? false)
        XCTAssertEqual(outcome.observation?.anomalyReason, "missing_exit")
    }

    func testCrossMidnightSessionIsAttributedToStartDay() throws {
        let logs = [
            EnterModel(isOn: true, time: makeDate("2026-04-24T22:30:00Z")),
            EnterModel(isOn: false, time: makeDate("2026-04-25T02:15:00Z"))
        ]

        let startDayOutcome = builder.build(for: try AttendanceDay("2026-04-24"), logs: logs, workNormMinutes: 480)
        XCTAssertEqual(startDayOutcome.status, .observationBuilt)
        XCTAssertEqual(startDayOutcome.observation?.workedMinutes, 225)
        XCTAssertEqual(startDayOutcome.observation?.sessionsCount, 1)

        let nextDayOutcome = builder.build(for: try AttendanceDay("2026-04-25"), logs: logs, workNormMinutes: 480)
        XCTAssertEqual(nextDayOutcome.status, .notReady)
        XCTAssertNil(nextDayOutcome.observation)
    }
}

private extension AttendanceObservationBuilderTests {
    func makeDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
