import XCTest
@testable import AttendanceAnalysisService

final class AttendanceCoreSignalCalculatorTests: XCTestCase {
    func testCalculatesSignalsFromLastNValidDays() throws {
        let calculator = AttendanceCoreSignalCalculator(baselineWindowDays: 3)
        let output = calculator.calculate(
            target: makeObservation(day: "2026-04-21", firstEntryTime: "2026-04-21T09:30:00Z", workedMinutes: 420),
            history: [
                makeObservation(day: "2026-04-15", firstEntryTime: "2026-04-15T08:00:00Z", workedMinutes: 300),
                makeObservation(day: "2026-04-16", firstEntryTime: "2026-04-16T09:00:00Z", workedMinutes: 480),
                makeObservation(day: "2026-04-17", firstEntryTime: "2026-04-17T09:15:00Z", workedMinutes: 450),
                makeObservation(day: "2026-04-20", firstEntryTime: "2026-04-20T09:00:00Z", workedMinutes: 420)
            ],
            workNormMinutes: 480
        )

        XCTAssertEqual(output.status, .signalsReady)
        XCTAssertEqual(output.snapshot.historyDaysUsed, 3)
        XCTAssertEqual(output.snapshot.averageStartMinutes, 545)
        XCTAssertEqual(output.snapshot.stddevStartMinutes, 7.0711)
        XCTAssertEqual(output.snapshot.stddevWorkedMinutes, 24.4949)
        XCTAssertEqual(output.snapshot.zS, -2.4495)
        XCTAssertEqual(output.snapshot.zT, 3.5355)
        XCTAssertEqual(output.snapshot.f, 0.6667)
        XCTAssertEqual(output.debug.historyDays.map(\.day), ["2026-04-16", "2026-04-17", "2026-04-20"])
        XCTAssertEqual(output.debug.deficitHistoryDaysCount, 2)
    }

    func testReturnsInsufficientHistoryWithExplicitStatus() throws {
        let calculator = AttendanceCoreSignalCalculator(baselineWindowDays: 4)
        let output = calculator.calculate(
            target: makeObservation(day: "2026-04-21", firstEntryTime: "2026-04-21T09:00:00Z", workedMinutes: 480),
            history: [
                makeObservation(day: "2026-04-16", firstEntryTime: "2026-04-16T09:00:00Z", workedMinutes: 480),
                makeObservation(day: "2026-04-17", firstEntryTime: "2026-04-17T09:05:00Z", workedMinutes: 485),
                makeObservation(day: "2026-04-20", firstEntryTime: "2026-04-20T08:55:00Z", workedMinutes: 475)
            ],
            workNormMinutes: 480
        )

        XCTAssertEqual(output.status, .insufficientHistory)
        XCTAssertEqual(output.snapshot.historyDaysUsed, 3)
        XCTAssertNil(output.snapshot.averageStartMinutes)
        XCTAssertNil(output.snapshot.zS)
        XCTAssertEqual(output.debug.calculationNotes, ["insufficient_history:expected_4:found_3"])
    }

    func testZeroVarianceUsesDeterministicCap() throws {
        let calculator = AttendanceCoreSignalCalculator(baselineWindowDays: 3)
        let output = calculator.calculate(
            target: makeObservation(day: "2026-04-21", firstEntryTime: "2026-04-21T10:00:00Z", workedMinutes: 420),
            history: [
                makeObservation(day: "2026-04-16", firstEntryTime: "2026-04-16T09:00:00Z", workedMinutes: 480),
                makeObservation(day: "2026-04-17", firstEntryTime: "2026-04-17T09:00:00Z", workedMinutes: 480),
                makeObservation(day: "2026-04-20", firstEntryTime: "2026-04-20T09:00:00Z", workedMinutes: 480)
            ],
            workNormMinutes: 480
        )

        XCTAssertEqual(output.status, .signalsReady)
        XCTAssertEqual(output.snapshot.zS, -8)
        XCTAssertEqual(output.snapshot.zT, 8)
        XCTAssertEqual(output.debug.calculationNotes, ["z_s_used_zero_variance_cap", "z_t_used_zero_variance_cap"])
    }
}

private extension AttendanceCoreSignalCalculatorTests {
    func makeObservation(day: String, firstEntryTime: String, workedMinutes: Int) -> AttendanceCoreSignalCalculator.ObservationInput {
        AttendanceCoreSignalCalculator.ObservationInput(
            day: try! AttendanceDay(day),
            firstEntryTime: ISO8601DateFormatter().date(from: firstEntryTime)!,
            workedMinutes: workedMinutes
        )
    }
}
